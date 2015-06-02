# Ruby file to hold provider definition

begin
  require 'vcoworkflows'
  require 'json'
rescue LoadError => e
  if e.message =~ /vcoworkflows/
    puts ''
    puts '=========================================================='
    puts 'ERROR: unable to find required \'vcoworkflows\' gem!'
    puts 'Please install this gem before using this provider plugin.'
    puts '=========================================================='
    puts ''
    exit
  end
  raise e
end

module VaqueroIo
  # Platform
  class Platform
    # Provision
    module Provision
      # rubocop:disable MethodLength, LineLength
      # rubocop:disable CyclomaticComplexity, PerceivedComplexity

      # Provision
      # Given an environment hash, provision the requested resources
      # @param [Hash] env - Environment hash
      #  - named_nodes (Boolean) Are we naming our chef nodes instead of using fqdn?
      #  - username (String) vCO username
      #  - password (String) vCO password
      #  - watch (Boolean) Stick around to watch status of our jobs
      #  - watch_interval (Integer) How many seconds should we wait between updates when watching?
      #  - verify_ssl (Boolean) Perform TLS/SSL certificate validation
      #  - verbose (Boolean) run verbosely
      #  - dry_run (Boolean) Dry run; don't actually do anything.
      def provision(env = nil, options = {})
        # Let's build our options hash...
        options = {
          named_nodes:    true,
          username:       nil,
          password:       nil,
          watch:          false,
          watch_interval: 15,
          verify_ssl:     nil,
          verbose:        false,
          dry_run:        false
        }.merge(options)

        # Timekeeping
        start_time = Time.now

        puts "\nExecuting build!\n"

        running_jobs = {}
        wf = nil
        env['components'].each do |name, component|
          # Get the workflow.
          if wf.nil?
            # This is our first time. Be gentle.

            # -------------------------------------------------------
            # SSL is hard, and we should smartly default to verifying
            # the server certificates because security, unless we
            # were told to ignore it. So, figure that out.
            # -------------------------------------------------------
            # If we didn't specify on the command line
            if options[:verify_ssl].nil?
              # Default to true unless specified in the component definition
              verify_ssl = component['verify_ssl'].nil? ? true : component['verify_ssl']
            else
              verify_ssl = options[:verify_ssl]
            end

            # yay ssl!
            # -------------------------------------------------------

            # Start by pulling config from the default configuration file
            config = VcoWorkflows::Config.new

            # update any parameters we were passed
            config.url        = component['vco_url'] if component['vco_url']
            config.username   = options[:username] if options[:username]
            config.password   = options[:password] if options[:password]
            config.verify_ssl = verify_ssl

            # Create an options hash for the workflow
            wfoptions = { config: config }

            # Use the workflow GUID if one is provided in the component data
            wfoptions[:id] = component['workflow_id'] ? component['workflow_id'] : nil

            # Create the workflow
            wf = VcoWorkflows::Workflow.new(component['workflow_name'], wfoptions)

            # create an array for this workflow if it doesn't already exist
            running_jobs[wf.id] = [] unless running_jobs[wf.id]
          else
            # This isn't my first rodeo

            id = nil
            if component['workflow_id']
              id = component['workflow_id']
            else
              id = wf.id if component['workflow_name'].eql?(wf.name)
            end

            # Steal the workflow name and WorkflowService from our last go-around
            wf = VcoWorkflows::Workflow.new(wf.name, id: id, service: wf.service)

            # create an array for this workflow if it doesn't already exist
            running_jobs[wf.id] = [] unless running_jobs[wf.id]
          end

          # Set the parameters and execute
          # If we're doing named nodes (i.e., chef nodes have specific names
          # per the node naming convention in the platform definition), then
          # we need to submit every individual node build request to the
          # workflow separately.
          if options[:named_nodes]
            # quick sanity check; if number of nodes != count, fail
            if component['nodes'].size != component['count']
              fail(IOError, 'Requested to build specific named nodes but number of nodes does not match count!')
            end

            # Fire off the build requests for each of the named nodes
            component['nodes'].each do |node|
              wf.parameters = set_parameters(name, component, env['product'], env['environment'], node)
              print "Requesting '#{wf.name}' execution for component #{name}, node #{node}..."
              running_jobs[wf.id] << execute(wf, options[:dry_run], options[:verbose])
            end

            # Otherwise, we don't care what anything is named in chef, so submit
            # build requests for the whole batch of components at once.
          else
            wf.parameters = set_parameters(name, component, env['product'], env['environment'])
            print "Requesting '#{wf.name}' execution for component #{component}..."
            running_jobs[wf.id] << execute(wf, options[:dry_run], options[:verbose])
          end
        end

        return if options[:dry_run]
        puts "\nThe following executions of #{wf.name} have been submitted:"
        running_jobs.each_key do |wfid|
          puts "- Workflow #{wfid}"
          running_jobs[wfid].each do |execution|
            puts "  - #{execution}"
          end
        end

        # If we've been asked to watch things, do so
        watch_executions(wf.service, running_jobs, start_time, options[:watch_interval]) if options[:watch]
      end
      # rubocop:enable MethodLength, LineLength
      # rubocop:enable CyclomaticComplexity, PerceivedComplexity

      # Execute the constructed workflow
      # @param [VcoWorkflows::Workflow] workflow Prepared workflow for execution
      # @param [Boolean] dry_run flag for whether this is a dry-run or not
      def execute(workflow = nil, dry_run = false, verbose = false)
        execution_id = nil
        if dry_run
          puts "\nNot executing workflow due to --dry-run.\n"
          puts "Workflow data (--verbose):\n#{workflow}\n" if verbose
        else
          execution_id = workflow.execute
          puts " (#{workflow.token.id})"
        end
        execution_id
      end
      #

      # rubocop: disable LineLength, MethodLength

      # set_parameters - Set up the input parameter hash for the workflow from
      # our environment definition for the current component.
      # @param [String] name Name of the current component
      # @param [Hash] component Hash of component definition data
      # @return [Hash] Input parameter hash for given to the workflow object
      def set_parameters(name, component, product, environment, nodename = nil)
        params                 = {}
        params['component']    = name
        params['businessUnit'] = product
        params['environment']  = environment
        params['onBehalfOf']   = component['execute_on_behalf_of']
        params['reservation']  = component['reservation_policy']
        params['coreCount']    = component['compute']['cpu']
        params['ramMB']        = component['compute']['ram']
        params['image']        = component['compute']['image']
        params['location']     = component['location'] if component['location']

        params['runlist'] = []
        params['runlist'] += component['run_list'] if component['run_list']
        params['runlist'] << component['component_role'] if component['component_role']

        if nodename.nil?
          params['machineCount'] = component['count']
        else
          params['machineCount'] = 1
          params['nodename']     = nodename
        end

        # TODO: figure out how we're going to handle attributes / tags
        # attributes::tags are marked required in the provider definition,
        # so we'll just assume they're present. Health check should fail
        # before we get here.
        # params['attributesJS'] = component['attributes']['tags'].to_json

        params
      end
      # rubocop:enable MethodLength, LineLength

      # rubocop:disable MethodLength, LineLength

      def watch_executions(wf_service = nil, running_jobs = {}, start_time = nil, watch_interval)
        # ===================================================================
        # Wait for all the requested workflows to complete
        #
        puts "\nWaiting for the following executions to complete:"
        running_jobs.each_key do |wf_id|
          puts "- Workflow #{wf_id}"
          running_jobs[wf_id].each do |execution_id|
            puts "  - #{execution_id}"
          end
        end

        puts "Will wait #{watch_interval} seconds between checks."

        while running_jobs.size > 0
          sleep watch_interval

          puts "\nChecking on running workflows (#{Time.now})..."
          running_jobs.each_key do |wf_id|
            puts "- #{wf_id}"
            running_jobs[wf_id].each do |execution_id|
              wf_token = VcoWorkflows::WorkflowToken.new(wf_service, wf_id, execution_id)
              print "  - #{execution_id} #{wf_token.state}"
              if wf_token.alive?
                puts ''
              else
                puts "; Run time #{(wf_token.end_date - wf_token.start_date) / 1000} seconds"
                running_jobs[wf_id].delete(execution_id)
                wf_token.output_parameters.each do |k, v|
                  puts "   #{k}: #{v}"
                end
              end
            end
            running_jobs.delete(wf_id) if running_jobs[wf_id].size == 0
          end
        end

        end_time = Time.now
        puts ''
        puts 'All workflows completed.'
        puts "Started:  #{start_time}"
        puts "Finished: #{end_time}"
        puts "Total #{format('%2f', end_time - start_time)} seconds"
      end
      # rubocop:enable MethodLength, LineLength
    end
  end
end

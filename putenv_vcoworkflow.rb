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

module Putenv
  # Platform
  class Platform
    # Provision
    module Provision
      # rubocop:disable MethodLength, LineLength

      # Provision
      # Given an environment hash, provision the requested resources
      # @param [Hash] env - Environment hash
      def provision(env = nil, options = {})
        # Let's build our options hash...
        options = {
          named_nodes: true,
          username: nil,
          password: nil,
          verify_ssl: true,
          verbose: false,
          dry_run: false
        }.merge(options)

        puts "\nExecuting build!\n"

        running_jobs = []
        wf = nil
        env['components'].each do |name, component|
          # Get the workflow.
          if wf.nil?
            # Steal the VcoWorkflows CLI auth class to yank values from the
            # environment if we weren't given anything useful
            auth = VcoWorkflows::Cli::Auth.new(username: options[:username],
                                               password: options[:password])
            wfoptions = {
              url:        component['vco_url'],
              username:   auth.username,
              password:   auth.password,
              verify_ssl: false
            }
            # Use the workflow GUID if one is provided in the component data
            wfoptions[:id] = component['workflow_id'] ? component['workflow_id'] : nil
            wf = VcoWorkflows::Workflow.new(component['workflow_name'], wfoptions)
          else
            # id = component['worfklow_id'] ? component['workflow_id'] : nil
            id = nil
            if component['workflow_id']
              id = component['workflow_id']
            else
              id = wf.id if component['workflow_name'].eql?(wf.name)
            end
            wf = VcoWorkflows::Workflow.new(wf.name, id: id, service: wf.service)
          end

          # Set the parameters and execute
          # If we're doing named nodes (i.e., chef nodes have specific names
          # per the node naming convention in the platform definition), then
          # we need to submit every indivitual node build request to the
          # workflow separately.
          if options[:named_nodes]
            # quick sanity check; if number of nodes != count, fail
            if component['nodes'].size != component['count']
              fail(IOError, "Requested to build specific named nodes but number of nodes does not match count!")
            end

            # Fire off the build requests for each of the named nodes
            component['nodes'].each do |node|
              wf.parameters = set_parameters(name, component, env['product'], env['environment'], node)
              print "Requesting '#{wf.name}' execution for component #{name}, node #{node}..."
              execute(wf, options[:dry_run], options[:verbose])
            end

            # Otherwise, we don't care what anything is named in chef, so submit
            # build requests for the whole batch of components at once.
          else
            wf.parameters = set_parameters(name, component, env['product'], env['environment'])
            print "Requesting '#{wf.name}' execution for component #{component}..."
            execute(wf, options[:dry_run], options[:verbose])
          end
        end

        return if options[:dry_run]
        puts "\nThe following executions of #{wf.name} have been submitted:"
        running_jobs.each do |job|
          puts "  - #{job}"
        end
      end
      # rubocop: enable MethodLength, LineLength

      # Execute the constructed workflow
      # @param [VcoWorkflows::Workflow] workflow Prepared workflow for execution
      # @param [Boolean] dry_run flag for whether this is a dry-run or not
      def execute(workflow = nil, dry_run = false, verbose = false)
        if dry_run
          puts "\nNot executing workflow due to --dry-run.\n"
          puts "Workflow data (--verbose):\n#{workflow}\n" if verbose
        else
          running_jobs << workflow.execute
          puts " (#{workflow.token.id})"
        end
      end
        
      # rubocop: disable LineLength

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
        params['runlist']      = component['run_list'] + [component['component_role']]

        # TODO: figure out how we're going to handle attributes / tags
        # attributes::tags are marked required in the provider definition,
        # so we'll just assume they're present. Health check should fail
        # before we get here.
        # params['attributesJS'] = component['attributes']['tags'].to_json

        if !nodename.nil?
          params['machineCount'] = 1
          params['nodename']     = nodename
        else
          params['machineCount'] = component['count']
        end
        params
      end
    end
  end
end

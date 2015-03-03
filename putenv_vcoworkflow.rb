# Ruby file to hold provider definition

begin
  require 'vcoworkflows'
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
          verify_ssl: true
        }.merge(options)

        # ================================================================
        # Just do everything
        # ================================================================

        puts 'BUILDING ALL THE THINGS!!!'

        # Create our list of running jobs
        running_jobs = []

        # Pull auth from environment
        auth = VcoWorkflows::Cli::Auth.new

        # Get the workflow. We'll grab it from the platform orchestrator here
        # to get ourselves set up. When we actually iterate through the
        # components we'll refresh the workflow based on component data, in
        # case there is a customization for whatever reason.

        # Set the connection options
        wfoptions = {
          url: env['orchestrator']['vco_url'],
          username: auth.username,
          password: auth.password,
          verify_ssl: false
        }
        if env['orchestrator']['workflow_id']
          wfoptions[:id] = env['orchestrator']['workflow_id']
        end

        # Get the workflow
        wf = VcoWorkflows::Workflow.new(env['orchestrator']['workflow_name'], wfoptions)

        # For every component we're going to provision, translate the
        # attributes we need into a form for the underlying engine
        # (in this case, vcoworkflows gem), then execute it.
        env['components'].each do |name, component|
          # Get the workflow.
          # If the component workflow name is the same as the last workflow
          # we fetched, re-use the name and id to save on some API calls.
          # If it's not, see if there's an ID specified and get the new
          # workflow.
          if wf.name.eql?(component['workflow_name'])
            wf = VcoWorkflows::Workflow.new(wf.name, id: wf.id, service: wf.service)
          else
            id = component['workflow_id'] ? nil : component['workflow_id']
            wf = VcoWorkflows::Workflow.new(component['workflow_name'], id: id, service: wf.service)
          end

          # Set the parameters
          wf.parameters = set_parameters(name, component)

          # Execute the workfow and grab the execution ID for later use
          running_jobs << wf.execute
        end

        puts "The following executions of #{wf.name} have been submitted:"
        running_jobs.each do |job|
          puts "  - #{job}"
        end
      end
      # rubocop: enable MethodLength, LineLength

      # rubocop: disable LineLength

      # set_parameters - Set up the input parameter hash for the workflow from
      # our environment definition for the current component.
      # @param [String] name Name of the current component
      # @param [Hash] component Hash of component definition data
      # @return [Hash] Input parameter hash for given to the workflow object
      def set_parameters(name = nil, component = nil)
        params = {}
        params['component']    = name
        params['businessUnit'] = env['product']
        params['environment']  = env['environment']
        params['onBehalfOf']   = component['execute_on_behalf_of']
        params['reservation']  = component['reservation_policy']
        params['coreCount']    = component['compute']['cpu']
        params['ramMB']        = component['compute']['memory']
        params['image']        = component['compute']['image']
        params['location']     = component['location']
        params['runlist']      = component['run_list'] + [component['component_role']]
        params['machineCount'] = component['count']
        params
      end
    end
  end
end

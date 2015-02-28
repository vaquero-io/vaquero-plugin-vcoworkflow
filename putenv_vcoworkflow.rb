# Ruby file to hold provider definition

require 'vcoworkflows'

module Putenv
  # Platform
  class Platform
    # Provision
    module Provision
      # Provision
      #
      # Given an environment hash, provision the requested resources
      # @param [Hash] env - Environment hash
      def provision(env = nil, options = {})
        # Let's build our options hash...
        options = {
          component: nil,
          count: nil,
          node: nil
        }.merge(options)

        if options[:node] && options[:count]
          fail(IOError, 'Cannot specify both :node and :count!')
        end

        if options[:node] || options[:count] && !options[:component]
          fail(IOError, 'Must specify :component if requesting :node or :count!')
        end

        puts "called putenv-vcoworkflow with: #{env.to_yaml}"
        puts "and options #{options}"

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

        # Grab the service to make subsequent workflow calls simpler
        wf_service = wf.service
        wf_id = wf.id

        # For every component we're going to provision, translate the
        # attributes we need into a form for the underlying engine
        # (in this case, vcoworkflows gem), then execute it.
        env['components'].each do |name, component|
          # Build up a parameter array for the workflow from our environment
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

          # Get the workflow
          wf = VcoWorkflows::Workflow.new(workflow, id: wf_id, service: wf_service)

          # Set the parameters
          wf.parameters = params

          # Execute the workfow and grab the execution ID for later use
          running_jobs << wf.execute
        end

        puts "The following executions of #{wf.name} have been submitted:"
        running_jobs.each do |job|
          puts "  - #{job}"
        end
      end
    end
  end
end

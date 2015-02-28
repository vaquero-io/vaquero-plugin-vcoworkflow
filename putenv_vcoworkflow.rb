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

        puts "called putenv-vcoworkflow with: #{env.to_yaml}"

        # ================================================================
        # Just do everything
        # ================================================================

        puts 'BUILDING ALL THE THINGS!!!'

        # Create our list of running jobs
        running_jobs = []

        # Pull auth from environment
        auth = VcoWorkflows::Cli::Auth.new

        # Get the workflow
        wf = VcoWorkflows::Workflow.new(workflow,
                                        url: server,
                                        username: auth.username,
                                        password: auth.password,
                                        verify_ssl: false)
        # Grab the service to make subsequent workflow calls simpler
        wf_service = wf.service
        wf_id = wf.id

        # For every component we're going to provision, translate the
        # attributes we need into a form for the underlying engine
        # (in this case, vcoworkflows gem), then execute it.
        env['components'].each do |name, component|
          # TODO: Where do we deal with things like chefserver?

          # Build up a parameter array
          params = {}
          params['component']    = name
          params['businessUnit'] = env['product']
          params['environment']  = env['environment']
          params['onBehalfOf']   = component['executeas'] # TODO: This needs to be defined!
          params['reservation']  = component['reservation']
          params['coreCount']    = component['compute']['cpu']
          params['ramMB']        = component['compute']['memory']
          params['image']        = component['compute']['image']
          params['location']     = component['location']
          params['runlist']      = component['runlist'] + [component['componentrole']]
          params['machineCount'] = component['count']

          # Get the workflow
          wf = VcoWorkflows::Workflow.new(workflow, id: wf_id, service: wf_service)

          # Set the parameters
          wf.parameters = params

          # Execute the workfow and grab the execution ID for later use
          running_jobs << wf.execute
        end

        puts "The following executions of #{}"
      end
    end
  end
end

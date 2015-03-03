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

        @named_nodes = options[:named_nodes]

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
            wfoptions[:id] = component['workflow_id'] if component['workflow_id']
            wf = VcoWorkflows::Workflow.new(component['workflow_name'], wfoptions)
          else
            id = component['worfklow_id'] ? component['workflow_id'] : nil
            wf = VcoWorkflows::Workflow.new(wf.name, id: id, service: wf.service)
          end

          # Set the parameters
          if named_nodes
            component['nodes'].each { |node| wf.parameters = set_parameters(name, component, node) }
          else
            wf.parameters = set_parameters(name, component)
          end

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
      def set_parameters(name = nil, component = nil, nodename = nil)
        params                 = {}
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
        if @named_nodes && nodename.nil?
          fail(IOError, 'Attempting to build named nodes, but no node name set')
        elsif @named_nodes && !nodename.nil?
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

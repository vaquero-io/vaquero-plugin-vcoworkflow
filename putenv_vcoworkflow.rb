# Ruby file to hold provider definition
module Putenv
  class Platform
    module Provision

      def provision(env)
        puts "called putenv-vcoworkflow with: #{env.to_yaml}"
      end
    end
  end
end
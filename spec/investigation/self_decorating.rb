class SelfDecorating

  module Secret
    @@methods_to_alias = []
    def self.extended(base)
      unless @@methods_to_alias.empty?
        # only needs to be done once
        @@methods_to_alias.each do |target| 
          without_method = "#{target}_without_secret"
          klass = base.class
          method_defined_here = (klass.instance_methods(false) + klass.private_instance_methods(false)).include?(RUBY_VERSION < '1.9' ? target.to_s : target)
          unless method_defined_here 
            klass.send(:define_method, target) do |*args, &block|
              super(*args, &block)
            end
          end
          unless klass.method_defined?(without_method)
            klass.send(:alias_method, without_method, target)
          end
        end
        @@methods_to_alias.clear
      end
    end
  
    def foo
      'foo'
    end

    def self.methods_to_alias
      @@methods_to_alias
    end
  end

  def self.new
    c = super
    return c.extend SelfDecorating::Secret
  end

  def self.decorate(method)
    Secret.class_eval do
# Error raised calling super from an aliased method included from a module where
# method is declared (Ruby 1.8)
# http://redmine.ruby-lang.org/issues/show/734
#      define_method(method) do |*args,&block|
#        super
#      end
#      alias_method "#{method}_without_secret", method
      define_method(method) do |*args,&block|
        super(*args, &block) + ' with secret'
      end
      methods_to_alias << method
    end 
  end
end


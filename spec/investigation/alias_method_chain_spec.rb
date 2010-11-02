require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

module AliasMethodChainSpec # namespacing

describe "alias method chain" do

  module ModifiedAliasMethodChain
    # From Tammo Freese's patch:
    # https://rails.lighthouseapp.com/projects/8994/tickets/285-alias_method_chain-limits-extensibility
    def alias_method_chain(target, feature)
      punctuation = nil
      with_method, without_method = "#{target}_with_#{feature}#{punctuation}", "#{target}_without_#{feature}#{punctuation}"
      
      method_defined_here = (instance_methods(false) + private_instance_methods(false)).include?(RUBY_VERSION < '1.9' ? target.to_s : target)
      unless method_defined_here
        module_eval <<-EOS
          def #{target}(*args, &block)
            super
          end
        EOS
      end  
      
      alias_method without_method, target
  #    alias_method target, with_method
      
      target_method_exists = (instance_methods + private_instance_methods).include?(RUBY_VERSION < '1.9' ? with_method : with_method.to_sym) 
      raise NameError unless target_method_exists
      
      module_eval <<-EOS
        def #{target}(*args, &block)
          self.__send__(:'#{with_method}', *args, &block)
        end
      EOS
    end
  end
  
  module BasicAliasMethodChain
    def alias_method_chain(target, feature)
      punctuation = nil
      with_method, without_method = "#{target}_with_#{feature}#{punctuation}", "#{target}_without_#{feature}#{punctuation}"
      alias_method without_method, target
      alias_method target, with_method
    end
  end
  
  module Bar
    def bar
      'bar'
    end
  end
puts self 
puts self.object_id
puts Bar.object_id
  module Baz
    def baz
      'baz'
    end
  end
  
  module BazWithLess
    def self.included(base)
      base.alias_method_chain :baz, :less
    end
  
    def baz_with_less
      baz_without_less + ' less'
    end
  end
  
  class Foo
    extend ModifiedAliasMethodChain
    include Bar
  
    def foo_with_more
      foo_without_more + ' more' 
    end
  
    def foo
      'foo'
    end
    alias_method_chain :foo, :more
  
    def bar_with_less
      bar_without_less + ' less'
    end
    alias_method_chain :bar, :less
  
    include Baz
    include BazWithLess
  end
  
  class FooBasic
    extend BasicAliasMethodChain
    include Bar
  
    def foo_with_more
      foo_without_more + ' more' 
    end
  
    def foo
      'foo'
    end
    alias_method_chain :foo, :more
  
    def bar_with_less
      bar_without_less + ' less'
    end
    alias_method_chain :bar, :less
  
    include Baz
    include BazWithLess
  end

  it "test modified alias method chain" do
    f = Foo.new
    f.foo.should == 'foo more'
    f.foo_without_more.should == 'foo'
    f.foo_with_more.should == 'foo more'
    f.bar.should == 'bar less'
    f.bar_without_less.should == 'bar'
    f.bar_with_less.should == 'bar less'     
    f.baz.should == 'baz less'
    f.baz_without_less.should == 'baz'
    f.baz_with_less.should == 'baz less'
    Bar.class_eval do
      def bar
        'new bar'
      end
    end
    f.bar.should == 'new bar less'
    f.bar_without_less.should == 'new bar'
    f.bar_with_less.should == 'new bar less'
    Foo.class_eval do
      def baz_with_less
        'lesser' 
      end
    end
    f.baz_without_less.should == 'baz'
    f.baz_with_less.should == 'lesser'
    f.baz.should == 'lesser'
  end

  it "test basic alias method chain" do
    f = FooBasic.new
    f.foo.should == 'foo more'
    f.foo_without_more.should == 'foo'
    f.foo_with_more.should == 'foo more'
    f.bar.should == 'bar less'
    f.bar_without_less.should == 'bar'
    f.bar_with_less.should == 'bar less'
    Bar.class_eval do
      def bar
        'new bar'
      end
    end
    # no change
    f.bar.should == 'bar less'
    f.bar_without_less.should == 'bar'
    f.bar_with_less.should == 'bar less'
    Foo.class_eval do
      def baz_with_less
        raise
      end
    end
    # no error
    f.baz_without_less.should == 'baz'
    f.baz_with_less.should == 'baz less'
    f.baz.should == 'baz less'
  end
end

end

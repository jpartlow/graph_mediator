require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

module ModuleSuperSpec # namespacing

describe "module super" do

  before(:each) do
    module Baz
      def baz
        'baz'
      end
    end
 
    module Bar
      def bar
        'bar'
      end
    end
 
    class AbstractFoo
      def deeper_foo
        'deeper_foo'
      end
    end
    
    class Foo < AbstractFoo
      include Baz
      include Bar
      def foo
        'foo'
      end
    end
  end

  after(:each) do
    ModuleSuperSpec.__send__(:remove_const, :Baz)
    ModuleSuperSpec.__send__(:remove_const, :Bar)
    ModuleSuperSpec.__send__(:remove_const, :Foo)
    ModuleSuperSpec.__send__(:remove_const, :AbstractFoo)
  end

  it "should basically work" do
    f = Foo.new
    f.foo.should == 'foo'
    f.deeper_foo.should == 'deeper_foo'
    f.bar.should == 'bar'
    f.baz.should == 'baz'
  end

  it "should override baz and retain a reference to original in a module" do
    Bar.class_eval do
      def baz
        super
      end
      alias_method :baz_original, :baz
      def baz
        super + ' barred'
      end
    end
    f = Foo.new
    f.foo.should == 'foo'
    f.deeper_foo.should == 'deeper_foo'
    f.bar.should == 'bar'
    f.baz.should == 'baz barred'
    # ruby 1.8 issue (see insert_subclass_spec.rb as well)
    # http://redmine.ruby-lang.org/issues/show/734
    lambda { f.baz_original }.should raise_error(NoMethodError)
  end

  it "cannot alias a method higher up the chain from a module" do
    lambda { Bar.class_eval do
      alias_method :baz_original, :baz
    end }.should raise_error(NameError)
  end

  it "can call super from a method override in a module" do
    Bar.class_eval do
      def baz
        super + ' barred from module'
      end
    end
    f = Foo.new
    f.baz.should == "baz barred from module"
  end

end

end

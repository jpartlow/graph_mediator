require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

require 'investigation/self_decorating'

module DecoratingSubclassSpec # namespacing

describe "Decorating by extending object eigenclass" do

  module Other
  
    def dingo
      super
    end
    # super fails in dingo_without_other (see above)
    alias_method :dingo_without_other, :dingo
  
    def dingo
      super + " other"
    end
  
    def bat
      'bat'
    end
  end
  
  class SuperClass 
    def dingo
      'dingo'
    end
  end
  
  def reload_bar
    Object.send(:remove_const, :Bar) if Object.const_defined?(:Bar)
    instance_eval <<EOS
  module ::Bar
    def bar
      'modular bar'
    end
  end
EOS
  end
  
  class SubClass < SuperClass; end

  before(:each) do
    reload_bar
  end

  after(:all) do
    Object.__send__(:remove_const, :Bar)
  end

  it "should extend Foo::Secret" do
    f = SelfDecorating.new
    f.foo.should == 'foo'
  end

  context "with a new SelfDecorating" do

    before(:each) do
      load('investigation/self_decorating.rb')
    end

    after(:each) do
      Object.send(:remove_const, :SelfDecorating)
    end

    it "should be able to decorate methods in base after they are defined" do
      SelfDecorating.send(:define_method, :bar) { 'bar' }
      SelfDecorating.decorate :bar
      f = SelfDecorating.new
      f.bar.should == 'bar with secret'
      f.bar_without_secret.should == 'bar'
    end

    it "should be able to decorate methods in Secret before they are defined" do
      SelfDecorating.decorate :bar
      SelfDecorating.send(:define_method, :bar) { 'bar' }
      f = SelfDecorating.new
      f.bar.should == 'bar with secret'
      f.bar_without_secret.should == 'bar'
    end

    it "should not interfere with overrides in superclasses" do
      SelfDecorating.class_eval { include Bar }
      SelfDecorating.decorate :bar
      f = SelfDecorating.new
      f.bar.should == 'modular bar with secret'
      f.bar_without_secret.should == 'modular bar'
      Bar.class_eval { def bar; 'new bar'; end }
      f.bar_without_secret.should == 'new bar'
      f.bar.should == 'new bar with secret'
    end

    it "should not interfere with overrides in the base class" do
      SelfDecorating.class_eval do
        include Bar
        def bar
          "locally " + super
        end
      end
      SelfDecorating.decorate :bar
      f = SelfDecorating.new
      f.bar.should == 'locally modular bar with secret'
      f.bar_without_secret.should == 'locally modular bar'
    end

  end

  it "should test overriding superclass methods in a module" do
    s = SubClass.new
    s.dingo.should == 'dingo'
    SubClass.send(:include, Other)
    s.dingo.should == 'dingo other'
    s.dingo_without_other
    s.bat.should == 'bat'
  end
end

end

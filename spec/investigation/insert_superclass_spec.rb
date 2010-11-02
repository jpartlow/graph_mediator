require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

module InsertingSuperClassSpec # namespacing

describe "insert superclass" do

  module Decorator
    def decorate(*methods)
      methods.each do |m|
        alias_method "#{m}_without_decoration", m
        define_method(m) do |*args,&block|
          super + " decorated" 
        end
      end
    end 
  end
  
  def reload_foo
    [:Bar, :Foo, :SubFoo].each { |c| Object.send(:remove_const, c) if Object.const_defined?(c) }
    instance_eval <<EOS
  module ::Bar
    def second; 'bar second'; end
  end
  
  module Baz
    def super_method
      'super'
    end
  end
  
  class ::Foo
    extend Decorator
    include Bar
    include Baz
    module DecorateMe
      def first; 'first'; end
      def second; super + ' overridden'; end
      def third; 'third'; end
    end
    include DecorateMe
  
    def local
      'local'
    end
  
    decorate :first, :second, :third, :super_method, :local
  
    def third
      'broken'
    end
  end
  
  class ::SubFoo < Foo
    def first
      'sub ' + super
    end
    def first_without_decoration
      'sub ' + super
    end
    def second
      'sub ' + super
    end
    def second_without_decoration
      'sub ' + super
    end
  end
EOS
  end

  before(:each) do
    reload_foo
  end

  after(:all) do
    Object.__send__(:remove_const, :Bar)
    Object.__send__(:remove_const, :Foo)
  end

  it "should decorate the declared methods" do
    f = Foo.new
    f.first.should == "first decorated"
    f.first_without_decoration.should == "first"
  end

  it "should decorate superclass methods not declared in DecorateMe" do
    # the same case as the DecorateMe module
    f = Foo.new
    f.super_method.should == "super decorated"
    f.super_method_without_decoration.should == "super"
  end

  it "should not interfere with overrides of superclass methods in DecorateMe" do
    f = Foo.new
    f.second.should == "bar second overridden decorated"
    f.second_without_decoration.should == "bar second overridden"
  end

  it "has the issue that it raises errors attempting to decorate methods defined only in the base class" do
    f = Foo.new
    lambda { f.local }.should raise_error(NoMethodError) # not .should == 'local decorated'
    f.local_without_decoration.should.should == 'local'
  end

  it "has the issue that overrides in base class override decoration" do
    f = Foo.new
    f.third.should == 'broken' # not 'broken decorated'
    f.third_without_decoration.should == 'third'
  end

  it "should not interfere with external overrides of superclasses methods" do
    Bar.class_eval { def second; 'external'; end }
    f = Foo.new
    f.second.should == 'external overridden decorated'
    f.second_without_decoration.should == 'external overridden'
  end

  it "should allow subclasses to override decoration" do
    f = SubFoo.new
    f.first.should == 'sub first decorated'
    f.second.should == 'sub bar second overridden decorated'
  end

  it "should allow subclasses to override methods without decoration" do
    f = SubFoo.new
    f.first_without_decoration.should == 'sub first'
    f.second_without_decoration.should == 'sub bar second overridden'
  end

end

end

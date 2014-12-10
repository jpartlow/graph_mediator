require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

require 'dependents/child.rb'
require 'dependents/parent.rb'

module Dependents

  describe "GraphMediator instances should flag that they are being destroyed" do
    def load_track_destroy
      create_schema do |conn|
        conn.create_table(:track_destroys, :force => true) do |t|
          t.string :name
          t.integer :lock_version, :defaults => 0
          t.timestamps
        end
      end

      @destroy_callbacks = callbacks_ref = []
      c = Class.new(ActiveRecord::Base)
      Object.const_set(:TrackDestroy, c)
      c.class_eval do 
        include GraphMediator
        
        def destroy_without_callbacks
          callbacks << being_destroyed?
          super
        end
        define_method(:callbacks) { callbacks_ref }
      end
    end

    before(:each) do
      load_track_destroy
      @t = TrackDestroy.create!
    end

    it "should note that it is being destroyed" do
      @t.should_not be_being_destroyed
      @t.destroy
      @destroy_callbacks.should == [true]
      @t.should_not be_being_destroyed
      @t.should be_destroyed
    end
  end

  describe "Tests ability to destroy objects with dependents despite optimistic locking" do
  
    before(:all) do
      load 'dependents/schema.rb'
    end

    before(:each) do
      @p = Parent.create!(:name => 'foo')
      @c1 = @p.children.create(:marker => 'bar')
      @c2 = @p.children.create(:marker => 'baz')
    end  

    it "should not raise a stale object error when deleting a parent with dependents that are automagically destroyed by activerecord" do
      @p.should_not be_new_record
      @c1.should_not be_new_record
      @c2.should_not be_new_record
      @p.reload
      lambda { @p.destroy }.should_not raise_error(ActiveRecord::StaleObjectError)
    end

    it "does not matter whether the include or association is declared first" do
      rp = ReverseParent.create(:name => 'foo')
      c1 = rp.reverse_children.create(:marker => 'bar')
      c2 = rp.reverse_children.create(:marker => 'baz')
      rp.reload
      lambda { rp.destroy }.should_not raise_error(ActiveRecord::StaleObjectError)
    end

    # This is a vague test that our changes to destroy workflow don't choke
    # in the trivial case of an unstored instance.
    it "should be okay if call destroy on new object" do
      np = Parent.new(:name => 'foo')
      cp = np.children.new(:marker => 'bar')
      np.destroy.should == np # Nothing should be thrown
      np.should be_destroyed
      np.lock_version.should == 0
    end
  end
end

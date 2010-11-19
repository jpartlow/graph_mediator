require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

require 'reservations/party_lodging'
require 'reservations/lodging'
require 'reservations/party'
require 'reservations/reservation'

describe "GraphMediator locking scenarios" do

  before(:all) do
    load 'reservations/schema.rb'
  end

  before(:each) do
    @today = Date.today
    @handle1_r1 = Reservation.create!(:starts => @today, :ends => @today + 1, :name => 'foo')
    @handle2_r1 = Reservation.find(@handle1_r1.id)
  end

  it "should be possible to create an unattached dependent object" do
    Lodging.create!.should_not be_nil
  end

  it "should increment lock_version for save_without_mediation" do
    lambda {
      @handle1_r1.starts = @today - 1
      @handle1_r1.save_without_mediation
    }.should change(@handle1_r1, :lock_version).by(1)
  end

  context "with optimistic locking for the graph" do

    it "should raise Stale for conflicts updating root" do
      @handle2_r1.update_attributes(:name => 'bar')
      lambda { @handle1_r1.update_attributes(:name => 'baz') }.should raise_error(ActiveRecord::StaleObjectError)
      @handle1_r1.reload
      @handle1_r1.name.should == 'bar' 
    end

    # Creating root cannot conflict
    # because the rows do not exist until the mediation transaction completes
    # so no one else is in a position to write first

    # not possible?  ActiveRecord::Locking::Optimistic does not decorate :destroy
    # it "should raise stale for conflicts deleting root" do

    it "should raise Stale for conflicts creating children" do
      @handle2_r1.parties.create(:name => 'Bob')
      lambda { @handle1_r1.update_attributes(:name => 'baz') }.should raise_error(ActiveRecord::StaleObjectError)
    end

    context "with children" do
      
      before(:each) do
        @handle1_r1.mediated_transaction do
          @party1 = @handle1_r1.parties.create(:name => 'Bob')
          @party2 = @handle1_r1.parties.create(:name => 'Joe')
          @room1  = @handle1_r1.lodgings.create(:room_number => 1)
          @room2  = @handle1_r1.lodgings.create(:room_number => 2)
        end
        @handle2_r1.reload
      end

      it "should raise Stale for conflicts updating children and root" do
        @handle2_r1.parties.first.update_attributes(:name => 'Frank')
        lambda { @handle1_r1.update_attributes(:name => 'baz') }.should raise_error(ActiveRecord::StaleObjectError)
      end
 
      it "should raise Stale for conflicts updating just children" do
        @handle2_r1.parties.first.update_attributes(:name => 'Frank')
        # version has incremented because of update to party, so, :versioning touch fails
        lambda { @handle1_r1.mediated_transaction {} }.should raise_error(ActiveRecord::StaleObjectError)
      end

      it "should raise Stale for conflicts deleting children and touching root" do
        @handle2_r1.parties.first.destroy
        lambda { @handle1_r1.update_attributes(:name => 'baz') }.should raise_error(ActiveRecord::StaleObjectError)
      end

      it "should not raise stale because of updates to its own children counter_caches" do
        @handle1_r1.mediated_transaction do
          @handle1_r1.lodge(@party1, :in => @room1)
          @handle1_r1.parties.first.touch
        end 
      end

      it "should increment lock_version for the graph if a dependent is changed" do
        lambda {
          @handle1_r1.parties.first.touch
          @handle1_r1.reload
        }.should change(@handle1_r1, :lock_version).by(1)
      end

      context "with lock_version for dependent children" do

        before(:all) do
          create_schema do |conn|
            conn.add_column(:parties, :lock_version, :integer)
          end  
          Party.reset_column_information
        end

        after(:all) do
          create_schema do |conn|
            conn.remove_column(:parties, :lock_version)
          end
          Party.reset_column_information
        end

        it "will raise stale because of updates to its own children counter_caches" do
#          Reservation::MediatorProxy._graph_mediator_logger = TestLogger.new
          Reservation::MediatorProxy._graph_mediator_log_level = 0
          r = Reservation.create!(:starts => @today, :ends => @today)
          party, room = nil, nil
          r.mediated_transaction do
            party = r.parties.create(:name => 'Joe')
            room  = r.lodgings.create(:room_number => 1)
          end
          r.mediated_transaction do
            r.lodge(party, :in => room)
            lambda { party.touch }.should raise_error(ActiveRecord::StaleObjectError)
          end
        end

      end
    end

    context "within a mediated transaction" do

      it "should not raise stale for changes made within a mediated transaction" do
        lambda { @handle1_r1.mediated_transaction do
          @handle1_r1.parties.create(:name => 'Bob')          
        end }. should change(@handle1_r1, :lock_version).by(1)
      end

      it "should not raise stale for counter_caches within a mediated transaction" do
        lambda { @handle1_r1.mediated_transaction do
          @handle1_r1.parties.create(:name => 'Bob')
          @handle1_r1.update_attributes(:name => 'baz')
        end }.should change(@handle1_r1, :lock_version).by(1)
      end
    end
  end

end

module GraphMediatorLocking # namespace to prevent helper class conflicts

describe "GraphMediator locking scenarios for classes without counter_caches" do

  before(:all) do
    create_schema do |connection|
      connection.create_table(:foos, :force => true) do |t|
        t.string :name
        t.integer :lock_version, :default => 0
        t.timestamps
      end
  
      connection.create_table(:bars, :force => true) do |t|
        t.string :name
        t.belongs_to :foo
        t.timestamps
      end
    end
  end

  class Bar < ActiveRecord::Base
    belongs_to :foo
  end

  class Foo < ActiveRecord::Base
    include GraphMediator
    mediate :dependencies => Bar
    has_many :bars
  end

  before(:each) do
    @h1_foo1 = Foo.create(:name => 'one')
    @h2_foo1 = Foo.find(@h1_foo1.id)
  end

  it "should also raise Stale for conflicts updating root" do
# nothing to touch...
    @h2_foo1.update_attributes(:name => 'bar')
    lambda { @h1_foo1.update_attributes(:name => 'baz') }.should raise_error(ActiveRecord::StaleObjectError)
    @h1_foo1.reload
    @h1_foo1.name.should == 'bar' 
  end

  it "should raise Stale for conflicts deleting children and touching root" do
    @h1_foo1.bars << Bar.create! 
    @h2_foo1.bars.first.destroy
    lambda { @h1_foo1.update_attributes(:name => 'baz') }.should raise_error(ActiveRecord::StaleObjectError)
  end

  it "should increment lock_version for the graph if a dependent is added" do
    lambda {
      @h1_foo1.bars << Bar.create!
      @h1_foo1.reload
    }.should change(@h1_foo1, :lock_version).by(1)
  end

  it "should increment lock_version for the graph if a dependent is deleted" do
    @h1_foo1.bars << Bar.create!
    @h1_foo1.reload
    lambda {
      @h1_foo1.bars.first.destroy
      @h1_foo1.reload
    }.should change(@h1_foo1, :lock_version).by(1)
  end

end

end

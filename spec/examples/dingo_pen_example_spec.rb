require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require 'aasm'

# Okay I lied.  This example has dingos.

create_schema do |conn|
  
  conn.create_table(:dingo_pens, :force => true) do |t|
    t.integer :pen_number
    t.integer :dingos_count
    t.integer :feed_rate
    t.integer :biscuit_minimum
    t.integer :biscuit_maximum
    t.float :total_biscuits
    t.float :total_biscuit_weight
    t.integer :lock_version, :default => 0
    t.timestamps
  end
 
  conn.create_table(:dingos, :force => true) do |t|
    t.belongs_to :dingo_pen
    t.string :name
    t.string :breed
    t.integer :voracity
    t.integer :belly
    t.string :aasm_state
    t.integer :lock_version, :default => 0
    t.timestamps
  end

  conn.create_table(:biscuits, :force => true) do |t|
    t.belongs_to :dingo_pen
    t.string :type
    t.float :weight
    t.integer :amount
    t.integer :lock_version, :default => 0
    t.timestamps
  end

end

# A dingo.
class Dingo < ActiveRecord::Base
  belongs_to :dingo_pen, :counter_cache => true
  include AASM
  aasm_initial_state :hungry
  aasm_state :hungry, :exit => :eat_biscuits!
  aasm_state :satiated, :exit => :burn_biscuits!
  aasm_event :eat do
    transitions :from => :hungry, :to => :satiated, :guard => :full?
  end
  aasm_event :run do
    transitions :from => :satiated, :to => :hungry
  end

  def eat_biscuits!
#    puts "#{self}.eat_biscuits"
    update_attributes(:belly => (belly || 0) + dingo_pen.eat_biscuits(voracity))
  end

  def burn_biscuits!
#    puts "#{self}.burn_biscuits"
    update_attributes(:belly => 0)
  end

  def full?
#    puts "#{self}.full? #{belly}, #{voracity}"
    belly >= voracity
  end
end

# A bunch of biscuits.
class Biscuit < ActiveRecord::Base
  belongs_to :dingo_pen

  def consume_weight!(weight_to_consume)
    amount_to_consume = (weight_to_consume/weight).round
    amount_consumed = nil
    if amount >= amount_to_consume
      self.amount -= amount_to_consume
      amount_consumed = amount_to_consume
    else
      amount_consumed = amount    
      self.amount = 0
    end
    save!
    return amount_consumed * weight
  end
end

class BigBiscuit < Biscuit; end
class LittleBiscuit < Biscuit; end

class DingoPen < ActiveRecord::Base
  has_many :dingos
  has_many :biscuits

  include GraphMediator

  def purchase_biscuits
    puts :purchase_biscuits
  end

  mediate :purchase_biscuits,
    :dependencies => [Dingo, Biscuit],
    :when_reconciling => [:adjust_biscuit_supply, :feed_dingos],
    :when_cacheing => :calculate_biscuit_totals
  
  def adjust_biscuit_supply
#puts "\n* adjusting_biscuit_supply"
    biscuits.each do |b|
      b.update_attributes(:amount => DingoPen.shovel_biscuits((biscuit_minimum + biscuit_maximum)/2)) if b.amount < biscuit_minimum
    end
  end

  def feed_dingos
#puts "** feed_dingos #{dingos.inspect}"
    dingos.each { |d| d.eat! if d.hungry? }
  end

  def eat_biscuits(weight_desired)
#puts "** eat_biscuits #{weight_desired}"
    total_weight_consumed = 0
    weight_left_to_consume = weight_desired
    biscuits.each do |b|
      weight_consumed_from_bin = b.consume_weight!(weight_left_to_consume)
#puts "weight_consumed_from_bin #{b.inspect}: #{weight_consumed_from_bin}"
      total_weight_consumed += weight_consumed_from_bin
      weight_left_to_consume -= weight_consumed_from_bin
      break if weight_left_to_consume <= 0
    end 
#puts "total_weight_consumed: #{total_weight_consumed}"
    return total_weight_consumed
  end

  def calculate_biscuit_totals
#puts "** calculate_biscuit_totals #{biscuits.inspect}"
    update_attributes(
      :total_biscuits => biscuits.sum('amount'),
      :total_biscuit_weight => biscuits.sum('weight * amount')
    )
  end

  # Class methods
  class << self
    # simulates the shoveling of biscuits into DingoPen feeders from the
    # theoretically BiscuitStore
    def shovel_biscuits(amount)
      return amount
    end
  end
end

describe "DingoPen" do

  before(:each) do
    @dingo_pen_attributes = {
      :pen_number => 42,
      :feed_rate => 10,
      :biscuit_minimum => 50,
      :biscuit_maximum => 100,
    }
  end

  it "should initialize" do
    dp = DingoPen.new
  end

  it "should create" do
    dp = DingoPen.create!(@dingo_pen_attributes)
    dp.lock_version.should == 1
  end

  it "should create with dingos and biscuits" do
    dp = DingoPen.new(@dingo_pen_attributes)
    dp.dingos << Dingo.new(:name => "Spot", :breed => "Patagonian Leopard Dingo", :voracity => 10)
    dp.dingos << Dingo.new(:name => "Foo", :breed => "Theoretical Testing Dingo", :voracity => 5)
    dp.biscuits << BigBiscuit.new(:amount => 35, :weight => 2.0)
    dp.biscuits << LittleBiscuit.new(:amount => 75, :weight => 0.5)
    dp.save!
    dp.lock_version.should == 1
  end

  context "on create" do

    it "should succeed" do
      dp = DingoPen.new(@dingo_pen_attributes)
      dp.dingos << Dingo.new(:name => "Spot", :breed => "Patagonian Leopard Dingo", :voracity => 10)
      dp.dingos << Dingo.new(:name => "Foo", :breed => "Theoretical Testing Dingo", :voracity => 5)
      dp.biscuits << BigBiscuit.new(:amount => 35, :weight => 2.0)
      dp.biscuits << LittleBiscuit.new(:amount => 75, :weight => 0.5)
      dp.save!
      dp.reload
      dp.dingos_count.should == 2
      dp.dingos[0].belly.should == 10
      dp.dingos[1].belly.should == 6
      # biscuit amounts adjusted and dingos ate
      dp.total_biscuits.should == 142
      dp.total_biscuit_weight.should == 67 * 2 + 75 * 0.5
      dp.lock_version.should == 1
    end

    it "should succed without mediation" do
      begin
        DingoPen.disable_all_mediation!
        dp = DingoPen.new(@dingo_pen_attributes)
        dp.dingos << Dingo.new(:name => "Spot", :breed => "Patagonian Leopard Dingo", :voracity => 10)
        dp.dingos << Dingo.new(:name => "Foo", :breed => "Theoretical Testing Dingo", :voracity => 5)
        dp.biscuits << BigBiscuit.new(:amount => 35, :weight => 2.0)
        dp.biscuits << LittleBiscuit.new(:amount => 75, :weight => 0.5)
        dp.save!
        dp.reload
        dp.dingos_count.should == 2
        dp.total_biscuits.should be_nil
        dp.total_biscuit_weight.should be_nil
        dp.lock_version.should == 0
      ensure
        DingoPen.enable_all_mediation!
      end
    end

  end

  context "on update" do
    it "should update_calculations after every child" do
      dp = DingoPen.create!(@dingo_pen_attributes)
      dp.dingos << Dingo.new(:name => "Spot", :breed => "Patagonian Leopard Dingo", :voracity => 10)
      dp.dingos << Dingo.new(:name => "Foo", :breed => "Theoretical Testing Dingo", :voracity => 5)
      dp.biscuits << BigBiscuit.new(:amount => 35, :weight => 2.0)
      dp.biscuits << LittleBiscuit.new(:amount => 75, :weight => 0.5)
      dp.reload
      dp.dingos_count.should == 2
      dp.dingos[0].belly.should == 10
      dp.dingos[1].belly.should == 6
      # biscuit amounts adjusted and dingos ate
      dp.total_biscuits.should == 142
      dp.total_biscuit_weight.should == 67 * 2 + 75 * 0.5
      dp.lock_version.should == 5
    end

    it "should have updated calculations only once within a mediated transaction" do
      dp = DingoPen.create!(@dingo_pen_attributes)
      dp.mediated_transaction do
        dp.dingos << Dingo.new(:name => "Spot", :breed => "Patagonian Leopard Dingo", :voracity => 10)
        dp.dingos << Dingo.new(:name => "Foo", :breed => "Theoretical Testing Dingo", :voracity => 5)
        dp.biscuits << BigBiscuit.new(:amount => 35, :weight => 2.0)
        dp.biscuits << LittleBiscuit.new(:amount => 75, :weight => 0.5)
        dp.save!
      end
      dp.reload
      dp.dingos_count.should == 2
      dp.dingos[0].belly.should == 10
      dp.dingos[1].belly.should == 6
      # biscuit amounts adjusted, and dingos ate
      dp.total_biscuits.should == 142
      dp.total_biscuit_weight.should == 67 * 2 + 75 * 0.5
      dp.lock_version.should == 2
    end
  end

  context "on delete" do
    it "should test delete"
  end
end

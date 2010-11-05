create_schema do |connection|
  connection.create_table(:reservations, :force => true) do |t|
    t.string :name
    t.date :starts
    t.date :ends
    t.integer :parties_count
    t.integer :lodgings_count
    t.integer :lock_version, :default => 0
    t.timestamps
  end
  
  connection.create_table(:parties, :force => true) do |t|
    t.string :name
    t.belongs_to :reservation
    t.integer :party_lodgings_count
    t.timestamps
  end
  
  connection.create_table(:lodgings, :force => true) do |t|
    t.integer :room_number
    t.decimal :rate
    t.belongs_to :reservation
    t.date :date
    t.integer :party_lodgings_count
    t.timestamps
  end
  
  connection.create_table(:party_lodgings, :force => true) do |t|
    t.belongs_to :party
    t.belongs_to :lodging
    t.timestamps
  end
end

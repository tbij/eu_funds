require 'fastercsv'
require 'roo'
require 'morph'

class FundRecord
  include Morph
end

class DataLoader

  def get_fields(file_name)
    fund_files   = load_fund_files(file_name)
    attributes   = fund_files.first.class.morph_attributes
    fields       = [:fund_file_id] + attributes.select{|a| a.to_s[/_field$/]}
    fields.collect do |field| 
      field = field.to_s.sub(/_field$/,'')
      if field[/^amount_/]
        [field.sub('amount_','').to_sym, field.to_sym]
      else
        field.to_sym
      end
    end.flatten
  end

  def setup_database file_name
    fields = get_fields(file_name)
    reset_database fields
  end

  def load_database file_name
    migrate_database
    fund_files = load_fund_files file_name
    files_with_data = with_data(fund_files)
    populate_database fund_files, files_with_data
  end
  
  def with_data fund_files
    fund_files.select do |f| 
      !f.parsed_data_file.blank? && 
        !f.parsed_data_file[/no data in pdf/] && 
        !f.parsed_data_file[/^it_/] && 
        !f.parsed_data_file[/pl_allregions_esf.csv/]
    end
  end

  def cmd line
    puts line
    puts `#{line}`
  end

  def add_index
    Dir.chdir(RAILS_ROOT)
    fund_items_migration = Dir.glob("#{RAILS_ROOT}/db/migrate/*_create_fund_items.rb").first
    text = IO.read(fund_items_migration)
    File.open(fund_items_migration, 'w') do |f|
      f.write text.sub(%Q|t.timestamps
    end|, 
    %Q|t.timestamps
    end
    add_index :fund_items, :fund_file_id|)
    end
    fund_file_countries_migration = Dir.glob("#{RAILS_ROOT}/db/migrate/*_create_fund_file_countries.rb").first
    text = IO.read(fund_file_countries_migration)
    File.open(fund_file_countries_migration, 'w') do |f|
      f.write text.sub(%Q|t.timestamps
    end|, 
    %Q|t.timestamps
    end
    add_index :fund_file_countries, :fund_file_id
    add_index :fund_file_countries, :country_id
    |)
    end
  end

  def add_associations
    File.open("#{RAILS_ROOT}/app/models/national_fund_file.rb", 'w') do |f|
      f.write %Q|class NationalFundFile < FundFile
end|
    end
    File.open("#{RAILS_ROOT}/app/models/transnational_fund_file.rb", 'w') do |f|
      f.write %Q|class TransnationalFundFile < FundFile
end|
    end
    File.open("#{RAILS_ROOT}/app/models/crossborder_fund_file.rb", 'w') do |f|
      f.write %Q|class CrossborderFundFile < FundFile
end|
    end
    File.open("#{RAILS_ROOT}/app/models/fund_file.rb", 'w') do |f|
      f.write %Q|class FundFile < ActiveRecord::Base
  has_many :fund_items
  has_many :countries, :through => :fund_file_countries
end|
    end
    File.open("#{RAILS_ROOT}/app/models/country.rb", 'w') do |f|
      f.write %Q|class Country < ActiveRecord::Base
      has_many :fund_file_countries
      has_many :fund_files, :through => :fund_file_countries
end|
    end
    File.open("#{RAILS_ROOT}/app/models/fund_file_country.rb", 'w') do |f|
      f.write %Q|class FundFileCountry < ActiveRecord::Base
      belongs_to :country
      belongs_to :fund_file
end|
    end
  end

  def reset_database fields
    destroy_migration.each_line {|line| cmd line.strip }
    country_migration.each_line {|line| cmd line.strip }
    fund_file_migration.each_line {|line| cmd line.strip }
    fund_item_migration(fields).each_line {|line| cmd line.strip }
    add_index
  end

  def migrate_database
    %Q|rake db:migrate RAILS_ENV=#{RAILS_ENV} --trace
    rake db:reset RAILS_ENV=#{RAILS_ENV} --trace
    rm spec/controllers/*_controller_spec.rb|.each_line {|line| cmd line.strip }
    
    if RAILS_ENV == 'development'
      cmd "rake db:test:clone_structure RAILS_ENV=#{RAILS_ENV}"
    end

    add_associations
  end
  
  def populate_database fund_files, files_with_data
    fund_files.each do |fund_file|
      saved_fund_file = save_fund_file(fund_file) 
      if saved_fund_file && files_with_data.include?(fund_file)
        records = load_fund_file(fund_file, saved_fund_file) 
        if records
          records.each do |record|
            save_record record
          end
        else
          puts "ERROR: no records for #{fund_file.parsed_data_file}"
        end
      end
    end
  end

  def get_direct_link fund_file
    direct_link = if !fund_file.direct_link_to_pdf.blank?
      fund_file.direct_link_to_pdf
    elsif !fund_file.direct_link_to_excel.blank?
      fund_file.direct_link_to_excel
    elsif !fund_file.direct_link_to_html.blank?
      fund_file.direct_link_to_html
    elsif !fund_file.direct_link_to_doc.blank?
      fund_file.direct_link_to_doc
    else
      fund_file.uri_to_landing_page
    end
  end

  def save_fund_file fund_file
    direct_link = get_direct_link fund_file
    country = country_model.find_or_create_by_name(fund_file.country_or_countries)

    attributes = {
        :region => fund_file.region,
        :program => fund_file.program,
        :sub_program => fund_file.sub_program_information,
        :original_file_name => fund_file.original_file_name,
        :parsed_data_file => fund_file.parsed_data_file,
        :direct_link => direct_link
    }
    if model = fund_file_model(fund_file)
      fund_file = model.create attributes
      fund_file_country_model.create({:country_id => country.id, :fund_file_id => fund_file.id})
      fund_file
    else
      nil
    end
  end

  def country_model
    eval('Country')
  end

  def fund_file_country_model
    eval('FundFileCountry')
  end

  def fund_file_model(fund_file)
    case fund_file.level.strip
    when /^national/i
      eval('NationalFundFile')
    when /^trans/i
      eval('TransnationalFundFile')
    when /^cross/i
      eval('CrossborderFundFile')
    when /^quango/i
      puts 'ignoring quango'
    else
      raise "unrecognized level: #{fund_file.level}"
    end
  end

  def save_record record
    record_model.create record.morph_attributes
  end

  def record_model
    eval('FundItem')
  end

  def row_not_empty(s, row)
    s.cell(row,1) ? true : false
  end

  def convert excel_file
    sheet = Excel.new(excel_file)
    raise 'expected value in first cell' unless row_not_empty(sheet, 1)
    FasterCSV.generate do |csv|
      1.upto(sheet.last_row) do |row_index|
        row = []
        1.upto(sheet.last_column) do |col|
          row << sheet.cell(row_index, col)
        end
        csv << row
      end
    end
  end

  def convert_to_morph_method_name label
    name = label.to_s.downcase.tr('()\-*',' ').gsub('%','percentage').gsub("'",'_').gsub('/','_').strip.chomp(':').strip.gsub(/\s/,'_').squeeze('_')
    name = '_'+name if name =~ /^\d/
    name.sub!('operación','operacion')
    name
  end

  def load_fund_files file_name
    csv = IO.read(file_name)
    csv.sub!('Country/Countries','Country_or_Countries')
    csv.sub!('Excel/PDF','Excel_or_PDF')
    csv.sub!('EU/Nation/Region','EU_or_Nation_or_Region')
    csv.sub!('Sub-region / ','Sub-region_or_')
    fund_files = Morph.from_csv(csv, 'FundFileProxy')
    fund_files
  end

  def field_names fund_file
    attributes   = fund_file.class.morph_attributes
    fields       = attributes.select{|a| a.to_s[/_field$/]}
    field_names  = fields.collect do |field|
      normalized = field.to_s.sub(/_field$/,'').to_sym
      original = fund_file.send(field)
      [normalized, original]
    end
    field_names.select {|x| !x[1].blank?}
  end
  
  def destroy_migration
    %Q|./script/destroy scaffold_resource fund_file_country\n| +
    %Q|./script/destroy scaffold_resource country\n| +
    %Q|./script/destroy scaffold_resource fund_item\n| +
    %Q|./script/destroy scaffold_resource fund_file|
  end

  def country_migration
    %Q|./script/generate scaffold_resource country name:string|
  end

  def fund_file_migration
    %Q|./script/generate scaffold_resource fund_file type:string error:text region:string program:string sub_program:string original_file_name:string parsed_data_file:string direct_link:string\n| +
    %Q|./script/generate scaffold_resource fund_file_country country_id:integer fund_file_id:integer|
  end

  def fund_item_migration fields
    attr_definitions = fields.collect do |field|
      case field.to_s
      when 'fund_file_id'
        'fund_file_id:integer'
      when /^amount_/
        "#{field}:integer"
      else
        "#{field}:string"
      end
    end
    attributes = (attr_definitions + ['fund_file_id:integer']).uniq.join(' ')
    %Q|./script/generate scaffold_resource fund_item #{attributes}|
  end

  def csv_from_file file_name
    return nil if !File.exist?(file_name)
    puts 'opening ' + file_name
    csv = case File.extname(file_name)
    when '.xls'
      convert file_name
    when '.csv'
      IO.read(file_name)
    else
      raise "unexpected file type: #{file_name}"
    end
  end

  def load_fund_file fund_file, saved_fund_file
    name = fund_file.parsed_data_file
    return nil if name.blank?
    country_code = name[0..1]
    file_name = "#{RAILS_ROOT}/DATA/#{country_code}/#{name}"
    csv = csv_from_file(file_name)
    return nil unless csv

    begin
      raw_records = FasterCSV.new csv, :headers => true
    rescue Exception => e
      if saved_fund_file
        saved_fund_file.error = "#{e.class.name}:\n#{e.to_s}\n\n#{e.backtrace.join("\n")}"
        saved_fund_file.save
      end
      return nil
    end

    field_names = field_names(fund_file)

    records = []
    begin
      raw_records.each do |row|
        record = FundRecord.new
        record.fund_file_id = saved_fund_file.id if saved_fund_file
  
        field_names.each do |field|
          normalized = field[0]
          original = field[1]
          begin
            value = row[original]
            if normalized.to_s[/^amount_(.+)$/]
              record.morph($1.to_sym, value)
              value = convert_value value
            end
            record.morph(normalized, value)
          rescue Exception => e
            if saved_fund_file
              saved_fund_file.error = "#{e.class.name}:\n#{e.to_s}\n\n#{e.backtrace.join("\n")}\n\n#{row.inspect}"
              saved_fund_file.save
            end
          end
        end
        records << record
      end
    rescue Exception => e
      if saved_fund_file
        saved_fund_file.error = "#{e.class.name}:\n#{e.to_s}\n\n#{e.backtrace.join("\n")}"
        saved_fund_file.save
      end
      return nil
    end
    
    records
  end

  def convert_value value
    unless value.blank?
      if value[/^([^\d]+)\d/]
        value = value.sub($1,'')
      end
      case value.strip
      when /^((\d|\.)*\,\d\d)( |$)/
        $1.gsub('.','').sub(',','.').to_i
      when /^((\d|\.)*\d\d\d)( |$)/
        $1.gsub('.','').to_i
      when /^((\d|\,)*\.\d\d?)( |$)/
        $1.gsub(',','').to_i
      when /^((\d|\,)*\d\d\d)( |$)/
        $1.gsub(',','').to_i
      end
    end
  end

end

require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe DataLoader do
  
  before :each do
    @loader = DataLoader.new
    @data_file = 'pl_in_progress_erdf.csv'

    @country = 'POLAND'
    @region = 'All regions'
    @program = 'ERDF'
    @sub_program = 'Media'
    @original_file = 'original_file_name'
    @direct_uri = 'http://example.com/'

    @fund_file = mock('fund_file',
        :parsed_data_file => @data_file,
        :country => @country,
        :region => @region,
        :program => @program,
        :sub_program_information => @sub_program,
        :original_file_name => @original_file,
        :direct_link_to_pdf => @direct_uri
        )
  end
  
  describe 'when loading database' do
    it 'should save fund file' do
      model = mock('FundFileClass')
      @loader.should_receive(:fund_file_model).and_return model
      fund_file_obj = mock('fund_file_obj')

      attributes = {
        :country => @country,
        :region => @region,
        :program => @program,
        :sub_program => @sub_program,
        :original_file_name => @original_file,
        :parsed_data_file => @data_file,
        :direct_link => @direct_uri
      }
      model.should_receive(:create).with(attributes).and_return(fund_file_obj)
      @loader.save_fund_file(@fund_file).should == fund_file_obj
    end

    it 'should reset database using first fund file record attributes, then populate database' do
      file_name = RAILS_ROOT+'/spec/fixtures/data/master.csv'
      first_fund = mock('first_fund', :parsed_data_file => 'parsed_data_file')
      fund_files = [ first_fund ]
      @loader.should_receive(:load_fund_files).with(file_name).and_return fund_files
      
      @loader.should_receive(:reset_database).with(first_fund)
      @loader.should_receive(:populate_database).with(fund_files)
      @loader.load_database file_name
    end
    
    it 'should run scaffold generate and reset db' do
      fund_file = mock('fund_file')
      file_migration_cmds = "first\nsecond"
      migration_cmds = "third\nfourth"
      record = mock('record')
      @loader.should_receive(:load_fund_file).with(fund_file).and_return [record]
      @loader.should_receive(:fund_file_migration).and_return file_migration_cmds
      @loader.should_receive(:fund_item_migration).with(record).and_return migration_cmds
      @loader.should_receive(:cmd).with('first')
      @loader.should_receive(:cmd).with('second')
      @loader.should_receive(:cmd).with('third')
      @loader.should_receive(:cmd).with('fourth')
      @loader.reset_database fund_file 
    end
    
    it 'should load fund file records in db' do
      fund_file = mock('fund_file')
      fund_file2 = mock('fund_file2')
      fund_files = [fund_file, fund_file2]

      record = mock('record')
      record2 = mock('record2')
      record3 = mock('record3')
      records = [record]
      records2 = [record2, record3]
      @loader.should_receive(:load_fund_file).with(fund_file).and_return records
      @loader.should_receive(:load_fund_file).with(fund_file2).and_return records2
      
      @loader.should_receive(:save_record).with(record)
      @loader.should_receive(:save_record).with(record2)
      @loader.should_receive(:save_record).with(record3)
      @loader.populate_database(fund_files)
    end
    
    it 'should save record' do
      morph_attributes = {:x => 'y'}
      record = mock('record', :morph_attributes => morph_attributes)
      model = mock('FundItemClass')
      @loader.should_receive(:record_model).and_return model
      model.should_receive(:create).with(morph_attributes).and_return mock('item') 
      @loader.save_record record
    end
    
  end

  describe 'when getting csv' do
    it 'should convert xls to csv' do
      converted = @loader.convert(RAILS_ROOT+'/spec/fixtures/data/pl/pl_in_progress_erdf.xls')
      converted.should == pl_csv
    end

    it 'convert an xls file to csv' do
      name = 'pl_in_progress_erdf.xls'
      file_name = RAILS_ROOT+'/DATA/pl/'+name
      File.should_receive(:exist?).with(file_name).and_return true
      @loader.should_receive(:convert).with(file_name).and_return pl_csv
      @loader.csv_from_file file_name
    end

    it 'should return contents of a csv file' do
      name = 'pl_in_progress_erdf.csv'
      file_name = RAILS_ROOT+'/DATA/pl/'+name
      File.should_receive(:exist?).with(file_name).and_return true
      IO.should_receive(:read).with(file_name).and_return pl_csv
      @loader.csv_from_file file_name
    end
    
    it 'should raise exception if not a csv or xls file' do
      name = 'pl_in_progress_erdf.doc'
      file_name = RAILS_ROOT+'/DATA/pl/'+name
      File.should_receive(:exist?).with(file_name).and_return true
      lambda { @loader.csv_from_file(file_name) }.should raise_exception      
    end
  end

  it 'should load CSV' do
    fund_file = fund_files.first
    fund_file.class.name.should == 'Morph::FundFile'
    fund_file.country.should == 'POLAND'
    fund_file.region.should == 'All regions'
    fund_file.program.should == 'ERDF'
    fund_file.parsed_data_file.should == 'pl_in_progress_erdf.csv'
    fund_file.original_file_name.should == 'Lista_beneficjentow_FE_zakonczone_030110.xls'
  end
  
  it 'should identify fields from fund_files' do
    files = fund_files
    field_names = @loader.field_names(files.first)
    field_names.first.should == [:beneficiary, :nazwa_beneficjenta] 
    field_names.second.should == [:project_title, :tytu_projektu]
    field_names.last.should == [:program_name, :program_operacyjny]
  end

  describe 'when parsed data file not present' do
    it 'should return nil for load_fund_file' do  
      fund_file = mock(:parsed_data_file => '')
      @loader.should_not_receive(:csv_from_file)
      records = @loader.load_fund_file fund_file
      # records.should be_nil
    end
  end

  describe 'when creating records' do
    before do
      file_name = RAILS_ROOT+'/DATA/pl/'+@data_file
  
      @loader.stub!(:csv_from_file).with(file_name).and_return pl_csv
      @loader.stub!(:field_names).with(@fund_file).and_return [
      [:beneficiary, :nazwa_beneficjenta],
      [:project_title, :tytuł_projektu],
      [:program_name, :program_operacyjny]
      ]
    end

    it 'should create a record for each row in fund file' do  
      records = @loader.load_fund_file @fund_file
      records.size.should == 2
      record = records.first
      record.country.should == 'POLAND'
      record.region.should == 'All regions'
      record.program.should == 'ERDF'
      record.beneficiary.should == '" Enter "Ośrodek Edukacyjno - Szkoleniowy  Barbara Wolska'
      record.project_title.should == 'Szansa 50+'
      record.program_name.should == 'Program Operacyjny Kapitał Ludzki'
  
      record = records.second
      record.country.should == 'POLAND'
      record.beneficiary.should == '"ARBOS" Irena Słabolepsza'
      record.project_title.should == 'Rozwój firmy ARBOS poprzez zakup rębaka do drewna'
      record.program_name.should == 'Regionalny Program Operacyjny Województwa Wielkopolskiego na lata 2007 - 2013'
    end
    
    it 'should return attribute names' do
      records = @loader.load_fund_file @fund_file
      @loader.attribute_names(records.first).should == [:country, :region, :program, :original_file_name, :beneficiary, :project_title, :program_name]
    end
    
    it 'should create fund_file_migration' do
      lines = @loader.fund_file_migration.split("\n")
      lines[0].should == %Q|./script/destroy scaffold_resource FundFile|
      lines[1].should == %Q|./script/generate scaffold_resource FundFile country:string region:string program:string sub_program:string original_file_name:string parsed_data_file:string direct_link:string|
    end

    it 'should create fund_item_migration' do
      records = @loader.load_fund_file @fund_file

      lines = @loader.fund_item_migration(records.first).split("\n")
      lines[0].should == %Q|./script/destroy scaffold_resource FundItem|
      lines[1].should == %Q|./script/generate scaffold_resource FundItem country:string region:string program:string original_file_name:string beneficiary:string project_title:string program_name:string|
      lines[2].should == %Q|rake db:migrate|
      lines[3].should == %Q|rake db:reset|
      lines[4].should == %Q|rm spec/controllers/fund_items_controller_spec.rb|
      lines[5].should == %Q|rake db:test:clone_structure|    
    end
  end

  def fund_files
    file_name = RAILS_ROOT+'/DATA/master.csv'
    IO.should_receive(:read).with(file_name).and_return master_csv
    fund_files = @loader.load_fund_files file_name
  end

  def pl_csv
%Q|Nazwa beneficjenta,Tytuł projektu,Program Operacyjny,Działanie,Poddziałanie,Wartość ogółem,Dofinansowanie publiczne,Rok przyznania dofinansowania,Rok wypłacenia ostatniej raty
""" Enter ""Ośrodek Edukacyjno - Szkoleniowy  Barbara Wolska",Szansa 50+,Program Operacyjny Kapitał Ludzki,7.2. Przeciwdziałanie wykluczeniu i wzmocnienie sektora ekonomii społecznej,7.2.1 Aktywizacja zawodowa i społeczna osób zagrożonych wykluczeniem społecznym,175864.0,174166.93,2008,2009
"""ARBOS"" Irena Słabolepsza",Rozwój firmy ARBOS poprzez zakup rębaka do drewna,Regionalny Program Operacyjny Województwa Wielkopolskiego na lata 2007 - 2013,Działanie 1.1. Rozwój mikroprzedsiębiorstw,Schemat I: Projekty inwestycyjne,48800.0,21000.0,2009,2009
|
  end
  
  def master_csv
%Q|Country,Region,Assigned to,Excel/PDF,Down-loaded,Scrape Needed,Priority,"Data
available
for
2007","Data
available
for
2008","Data
available
for
2009","Data
available
for2010",Program,"Sub-program
information",Parsed data file,Original file name,Currency Field,Beneficiary Field,Project Title Field,Program Name Field,Amount Allocated Field (EU Funds),Amount Allocated (All funds EU/Nation/Region),Amount Paid Field,Description Field,Year Field,Date Field,Start Year Field,,Direct link to PDF,"Direct link to
Excel","Direct Link to 
HTML",Direct link to Doc,,Last Updated,Next update ,Explanatory Notes,Waiting for response,Contact,Uri to landing page,Contact
POLAND,All regions,,Excel,Done,No,Tier 1,,,,,ERDF,Projects in Progress,pl_in_progress_erdf.csv,Lista_beneficjentow_FE_zakonczone_030110.xls,,Nazwa beneficjenta,Tytu_ projektu,Program Operacyjny,,,,,,,,,http://www.mrr.gov.pl/aktualnosci/fundusze_europejskie_2007_2013/Documents/Lista_beneficjentow_FE_030110.rar
|
  end

end

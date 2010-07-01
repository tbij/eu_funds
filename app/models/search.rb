require 'morph'
require 'google_translate' unless RAILS_ENV == 'test'
require 'fastercsv'

class Search

  include Morph

  attr_accessor :page, :per_page, :region, :country, :terms, :result_sets, :results, :total, :current_page, :total_pages

  def initialize page=1, per_page=15, region=nil, country=nil
    @page = page
    @per_page = per_page
    @region = region
    @country = country
  end

  def largest_result_set
    @result_sets.max{|a,b| a.total <=> b.total}
  end

  def countries
    summarize(@result_sets, :fund_country)
  end
  
  def regions
    summarize(@result_sets, :fund_region)
  end

  def split_terms(query)
    query.include?(' OR ') ? query.split(' OR ').compact.map(&:strip).map(&:downcase).uniq : translations(query)
  end
  
  def joined_terms
    @terms.join(' OR ')
  end
  
  def min_eu_amount_in_euros
    if @total == 0
      0
    else
      id_sets = @terms.collect { |term| do_search_ids(term, @total) }
      ids = id_sets.flatten.uniq.sort
      FundItem.sum(:amount_allocated_eu_funds, :conditions => "id in (#{ids.join(',')}) AND currency = 'EUR'")
    end
  end

  def all_results
    result_sets = @terms.collect { |term| do_search(term, @total) }
    @all_results = []
    result_sets.each do |result|
      result.each_hit_with_result do |hit, item|
        @all_results << item
      end
    end
    @all_results.uniq
  end

  def translate_and_search query
    @terms = split_terms(query)
    @result_sets = @terms.collect { |term| do_search(term) }
    
    # answer = {}
    # @terms.each_with_index {|e,i| answer[@terms[i]] = @result_sets[i].results.collect(&:beneficiary) }
    @results = []
    @total = 0
    
    require 'will_paginate'
    @result_sets.each do |result|
      @total += result.total
      @current_page = result.hits.current_page
      @total_pages = @total / @per_page

      result.each_hit_with_result do |hit, item|
        @results << item
      end
    end
    @results = @results.uniq
  end

  def do_search term, per_page=@per_page, page=@page, country=@country, region=@region
    FundItem.search :include => [:fund_file] do
      keywords term
      if region
        with :fund_region, region
        with :fund_country, country
      elsif country
        with :fund_country, country
      end
      facet :fund_country, :fund_region
      paginate :page => page, :per_page => per_page
    end
  end

  def do_search_ids term, per_page=@per_page, page=@page, country=@country, region=@region
    FundItem.search_ids do
      keywords term
      if region
        with :fund_region, region
        with :fund_country, country
      elsif country
        with :fund_country, country
      end
      facet :fund_country, :fund_region
      paginate :page => page, :per_page => per_page
    end
  end

  def translations term
    translator = Google::Translator.new
    translations = LANGUAGE_CODES.collect do |code|
      begin
        translator.translate('en', code, term)
      rescue Exception => e
        logger.error("#{e.class.name} #{e.to_s} #{e.backtrace.join("\n")}")
        nil
      end
    end.compact
    ([term] + translations).map(&:strip).map(&:downcase).uniq
  end

  def summarize result_sets, facet
    rows = result_sets.map {|x| x.facet(facet).rows }.flatten
    rows = rows.group_by(&:value)
    Struct.new("Facet", :value, :count)
    rows.keys.collect do |value|
      count = rows[value].collect {|r| r.count}.sum
      Struct::Facet.new value, count
    end
  end
  
  LANGUAGE_CODES = [
      'bg', # BULGARIA
      'cs', # CZECH REPUBLIC
      'da', # DENMARK
      'et', # ESTONIA
      'fi', # FINLAND
      'fr', # FRANCE, BELGIUM, LUXEMBOURG
      'de', # GERMANY, AUSTRIA
      'el', # GREECE, CYPRUS
      'hu', # HUNGARY
      'it', # ITALY
      'lv', # LATVIA
      'lt', # LITHUANIA
      'nl', # NETHERLANDS
      'pl', # POLAND
      'pt', # PORTUGAL
      'ro', # ROMANIA
      'sk', # SLOVAKIA
      'sl', # SLOVENIA
      'es', # SPAIN
      'sv'  # SWEDEN
      # 'en'  #'UK, IRELAND, MALTA
  ]
end
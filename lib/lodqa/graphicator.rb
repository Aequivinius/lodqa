#!/usr/bin/env ruby
# Parses a query and produces its parse rendering and PGP.
require 'net/http'

module Lodqa; end unless defined? Lodqa

# An instance of this class is initialized with a dictionary.
class Lodqa::Graphicator
  attr_reader :parser
  
  PARSERS = {
    :default => { :name => 'EnjuAccessor' , :file => 'enju_accessor' } ,
    :spacy => { :name => 'SpacyAccessor', :file => 'spacy_accessor' } ,
    :enju => { :name => 'EnjuAccessor' , :file => 'enju_accessor' } ,
    :parsey => { :name=> 'ParseyAccessor' , :file => 'parsey_accessor' }
  }

  def initialize(parser=nil, parser_url=nil)
    if !parser.nil? && parser_names = PARSERS[parser.downcase.to_sym]
    else parser_names = PARSERS[:default]
    end
    require 'accessors/' + parser_names[:file]
    @parser = eval("Accessor::" + parser_names[:name]).new(parser_url)
  end

  def parse(query)
    @parse = @parser.parse(query)
  end

  def get_rendering
    @parser.get_graph_rendering(@parse)
  end

  def get_pgp
    graphicate(@parse)
  end

  def graphicate (parse)
    nodes = get_nodes(parse)

    node_index = {}
    nodes.each_key{|k| node_index[nodes[k][:head]] = k}

    focus = node_index[parse[:focus]]
    focus = node_index.values.first if focus.nil?

    edges = get_edges(parse, node_index)
    graph = {
      :nodes => nodes,
      :edges => edges,
      :focus => focus
    }
  end

  def get_nodes (parse)
    nodes = {}

    variable = 't0'
    parse[:base_noun_chunks].each do |c|
      variable = variable.next;
      nodes[variable] = {
        :head => c[:head],
        :text => parse[:tokens][c[:beg] .. c[:end]].collect{|t| t[:lex]}.join(' ')
      }
    end

    nodes
  end

  def get_edges (parse, node_index)
    edges = parse[:relations].collect do |s, p, o|
      {
        :subject => node_index[s],
        :object => node_index[o],
        :text => p.collect{|i| parse[:tokens][i][:lex]}.join(' ')
      }
    end
  end

end

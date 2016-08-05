#!/usr/bin/env ruby
require 'graphviz'
require 'rest-client'


# Using require_relative for standalone use
require_relative '../accessors/graph'

# Abstract class for specific parser implementations
class Accessor
  NOUN_CHUNK_TAGS = ["NN", "NNP", "CD", "FW", "JJ"] 
  # wh-pronoun and wh-determiner
  WH_WORD_TAGS      = ["WP", "WDT"]
  # spaCy and enju mark cases such as 'Alzheimer's disease'
  # as follows:
  # Alzheimer/NNP 's/POS disease/NN
  # this is what we need this category for
  POSSESSIVE_TAGS = ["POS", "PO"]
  NOUN_CHUNK_HEAD_TAGS = ["NN", "NNP", "CD", "FW"]
  
  # connects to server
  def initialize(parser_url)
    @server = RestClient::Resource.new(parser_url)
    
    if !@server.instance_of? RestClient::Resource
      raise "Error creating resource, make sure you pass URL"
    end
  end
  
  # Takes sentence, returns hash with tokens, focus etc.
  def parse(sentence)
    tokens, root     = get_parse(sentence)
    base_noun_chunks = get_base_noun_chunks(tokens)
    focus            = get_focus(tokens, base_noun_chunks)
    relations        = get_relations(tokens, base_noun_chunks)
  
    { :tokens => tokens,  # The array of token parses
      :root   => root,    # The index of the root word
      # The index of the focus word, 
      # i.e., the one modified by a _wh_-modifier
      :focus  => focus,         
      :base_noun_chunks => base_noun_chunks, # the array of base noun chunks
      :relations => relations   # Shortest paths between two heads
    }  
  end
  
  
  # these functions are overwritten in the implementation
  def get_parse(s);end
  def get_base_noun_chunks(t);end
  def get_focus(t,b);end
  
  # shortest path between the head word of any two base noun chunks 
  # that are not separated by other base noun chunks.
  def get_relations(tokens, base_noun_chunks)
    graph = Graph.new
    tokens.each do |t|
      if t[:args]
        t[:args].each do |type, arg|
          graph.add_edge(t[:idx], arg, 1) if arg >= 0
        end
      end
    end
  
    rels = []
    heads = base_noun_chunks.collect{|c| c[:head]}
    base_noun_chunks.combination(2) do |c|
      path = graph.shortest_path(c[0][:head], c[1][:head])
      s = path.shift
      o = path.pop
      rels << [s, path, o] if (path & heads).empty?
    end
    return rels
  end
  
  # It returns the index of the focus word. For example:
  # "What devices are used to treat heart failure?"
  # will return "1" (devices).
  def get_focus(tokens, base_noun_chunks)
    # find the wh-word
    # assumption: one query has one wh-word
    wh = -1
    tokens.each do |t|
      if WH_WORD_TAGS.include?(t[:cat])
        wh = t[:idx]
        break
      end
    end
  
    focus = if wh > -1
              if tokens[wh][:args]
                tokens[wh][:args][0][1]
              else
                wh
              end
            elsif base_noun_chunks.any?
              base_noun_chunks[0][:head]
            else
              -1
            end
  end
  
  # generates a SVG expression that shows the predicate-argument
  # structure of the sentence
  def get_graph_rendering(parse)
    return '' if parse.nil? || parse[:root].nil?

    tokens = parse[:tokens]
    root   = parse[:root]
    focus  = parse[:focus]

    g = GraphViz.new(:G, :type => :digraph)
    g.node[:shape] = "box"
    g.node[:fontsize] = 10
    g.edge[:fontsize] = 9

    n = []
    tokens.each do |p|
      n[p[:idx]] = g.add_nodes(p[:idx].to_s, :label => "#{p[:lex]}/#{p[:pos]}/#{p[:cat]}")
    end

    tokens.each do |p|
      if p[:args]
        p[:args].each do |type, arg|
          if arg >= 0 then g.add_edges(n[p[:idx]], n[arg], :label => type) end
        end
      end
    end

    g.get_node(root.to_s).set {|_n| _n.color = "blue"} if root >= 0
    g.get_node(focus.to_s).set {|_n| _n.color = "red"} if focus >= 0
    g.output(:svg => String)
  end
end

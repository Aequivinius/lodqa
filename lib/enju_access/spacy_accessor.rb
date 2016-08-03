#!/usr/bin/env ruby

require 'rest-client'
require 'json'

# Using require_relative for standalone use
# of this file
require_relative '../enju_access/graph'

module EnjuAccess; end unless defined? EnjuAccess

# An instance of this class connects to an spaCy server to parse a sentence.
class EnjuAccess::SpacyAccessor
  attr_reader :enju

  NOUN_CHUNK_TAGS = ["NN", "NNP", "CD", "FW", "JJ"]
  WH_WORD_TAGS      = ["WP", "WDT"] # wh-pronoun and wh-determiner 
  # spaCy and enju mark cases such as 'Alzheimer's disease'
  # as follows:
  # Alzheimer/NNP 's/POS disease/NN
  # this is what we need this category for
  POSSESSIVE_TAGS = ["POS", "PO"]

  # It initializes an instance of RestClient::Resource
  # to connect to a spaCy server
  def initialize(spacy_url='http://spacy.dbcls.jp/spacy_rest')
    # FIXME: initialize is called with enju url
    # @spacy = RestClient::Resource.new('http://spacy.dbcls.jp/spacy_rest')
    @spacy = RestClient::Resource.new('http://spacy.dbcls.jp/spacy_rest')
    
    if !@spacy.instance_of? RestClient::Resource
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

  private

  # returns tokens and sentence root index
  def get_parse(sentence)
    return [[], nil] if sentence.nil? || sentence.strip.empty?
    sentence = sentence.strip
    
    # send the sentence to the server
    response = @spacy.post(:text => sentence)
    
    case response.code
    when 200 # 200 means success
      if response =~/^Empty line/
        raise "Empty response."
      end

      tokens = []
      root = nil
      # maps spaCy token ids to plain integers
      spacy_token_ids = Hash.new

      parsed = JSON.parse(response)
      
      # TODO: what's the difference between :pos and :cat?
      parsed['denotations'].each_with_index do |denotation , i|
        spacy_token_ids[denotation['id']] = i
        
        beginning = denotation['span']['begin']
        ending = denotation['span']['end'] 
        
        tokens << { 
          :idx => i, 
          :beg => beginning, 
          :end => ending, 
          # as the token appears in the text
          :lex => sentence[beginning...ending],
          :pos => denotation['obj'], # or is it token[:cat]?
          :cat => denotation['obj'][0..1] # FIXME: Not clean
        }
      end
      
      # treat every dependency as if it was
      # a predicate-argument relation
      parsed['relations'].each do |relation|
        # token in question
        i = spacy_token_ids[relation['obj']]
        
        # TODO: change this to show dependency type
        tokens[i][:args] ||= [] 
        argument_counter = "ARG" + (tokens[i][:args].size + 1).to_s
        
        # if the token is the root, we set ARG1 => -1
        if relation['pred'] == "ROOT"
          argument_token = -1
          root = i
        else
          argument_token = spacy_token_ids[relation['subj']]
        end   
        
        tokens[i][:type] = relation['pred']  
        tokens[i][:args] << [ argument_counter , argument_token ]      
      end

      return [tokens, root]
    else
      raise "No response from server."
    end
  end
  
  def get_base_noun_chunks(tokens)    
    base_noun_chunks = []
    
    within_noun_chunk = false    
    tokens.each_with_index do |token, i|
      # the first element in a noun chunk
      if NOUN_CHUNK_TAGS.include?(token[:cat]) && 
         !within_noun_chunk
        
        within_noun_chunk = true
        base_noun_chunks << { :beg => i}
      
      # special case: possesive 's
      # only accept if the next token is a NN
      elsif POSSESSIVE_TAGS.include?(token[:cat]) &&
            i+1 <= tokens.length &&
            NOUN_CHUNK_TAGS.include?(tokens[i+1][:cat])
      
        next
      end
      
      # element after the last element of noun chunk  
      if !NOUN_CHUNK_TAGS.include?(token[:cat]) && 
         within_noun_chunk
         
        base_noun_chunks[-1][:end] = i - 1
        base_noun_chunks[-1][:head] = i - 1
        within_noun_chunk = false
      end
      
      # or it's the last element of the query
      if within_noun_chunk && 
         i+1 == tokens.length
        
        base_noun_chunks[-1][:end] = i 
        base_noun_chunks[-1][:head] = i
        within_noun_chunk = false
      end
    end
    
    # assemble string
    base_noun_chunks.each do |chunk|
      chunk_string = ""
      chunk_tokens = tokens[chunk[:beg]..chunk[:end]]
      chunk_tokens.each_with_index do |chunk_token, i|
        chunk_string += chunk_token[:lex]
        
        if i+1 < chunk_tokens.length && 
           chunk_token[:end] < chunk_tokens[i+1][:beg]
          
          chunk_string += " "
        end 
        
      end
      chunk[:string] = chunk_string
    end
    
    return base_noun_chunks
  end

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
end

if __FILE__ == $0
  parser = EnjuAccess::SpacyAccessor.new("http://spacy.dbcls.jp/spacy_rest")
  parse = parser.parse("What genes are related to Alzheimer's disease?")
  parse[:tokens].each do |t|
    p t
  end
  puts "Root-----------------------------"
  p parse[:root]
  puts "Focus-----------------------------"
  p parse[:focus]
  puts "BNCs-----------------------------"
  p parse[:base_noun_chunks]
  puts "Heads----------------------------"
  p parse[:base_noun_chunks].collect{|c| c[:head]}
  puts "BNCs (token_begin, token_end)----"
  p parse[:base_noun_chunks].collect{|c| [c[:beg], c[:end]]}
  puts "Relations------------------------"
  p parse[:relations]
end

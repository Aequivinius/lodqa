#!/usr/bin/env ruby
#
# It takes a plain-English sentence as input and returns parsing results by accessing an Enju cgi server.
#
require 'rest-client'
require 'json'
require 'enju_access/graph'

module EnjuAccess; end unless defined? EnjuAccess

# An instance of this class connects to an Enju CGI server to parse a sentence.
class EnjuAccess::SpacyAccessor
  attr_reader :enju

  # FIXME: NC_CAT etc are bad names  
  # Noun-chunk elements
  # (Note that PRP is not included. For dialog analysis however PRP (personal pronoun) would need to be included.)
  NC_CAT      = ["NN", "NNP", "CD", "FW", "JJ"]
  
  # spaCy and enju mark cases such as 'Alzheimer's disease'
  # as follows:
  # Alzheimer/NNP 's/POS disease/NN
  POSSESIVE_TAGS = ["POS", "PO"]

  # Noun-chunk elements that may appear at the head position
  NC_HEAD_CAT = ["NN", "NNP", "CD", "FW"]

  # wh-pronoun and wh-determiner
  WH_CAT      = ["WP", "WDT"]

  # It initializes an instance of RestClient::Resource to connect to an Enju cgi server
  def initialize (enju_url)
    @enju = RestClient::Resource.new 'http://spacy.dbcls.jp/spacy_rest'
    raise "An instance of RestClient::Resource has to be passed as the first argument." unless @enju.instance_of? RestClient::Resource
  end

  # It takes a plain-English sentence as input, and
  # returns a hash that represent various aspects
  # of the PAS and syntactic structure of the sentence.
  def parse (sentence)
    tokens, root     = get_parse(sentence)
    base_noun_chunks = get_base_noun_chunks(tokens)
    focus            = get_focus(tokens, base_noun_chunks)
    relations        = get_relations(tokens, base_noun_chunks)
    puts base_noun_chunks, focus, relations


    {
      :tokens => tokens,  # The array of token parses
      :root   => root,    # The index of the root word
      :focus  => focus,   # The index of the focus word, i.e., the one modified by a _wh_-modifier
      :base_noun_chunks => base_noun_chunks, # the array of base noun chunks
      :relations => relations   # Shortest paths between two heads
    }
    
  end

  private

  # It populates the instance variables, tokens and root
  def get_parse (sentence)
    return [[], nil] if sentence.nil? || sentence.strip.empty?
    sentence = sentence.strip
    
    # send the sentence to the server
    # the @enju really should be renamed
    # but like this it easier to compare to CGIAccessor
    response = @enju.post :text => sentence
    
    case response.code
    when 200             # 200 means success
      raise "Empty input." if response =~/^Empty line/

      tokens = []
      root = nil
      # This one will map spaCy produced indexes (with prefixes)
      # to plain ints
      # this makes finding relations easier
      spacy_token_ids = Hash.new

      # the response is in JSON
      parsed = JSON.parse(response)

      # we look at every denotation, which contains the tag
      # CGIAccessor differentiates between :pos and :cat
      # The difference between them I haven't figured out yet, quite
      parsed['denotations'].each_with_index do |p , i|
        token = Hash.new
        token[:idx] = i
        token[:beg] = p['span']['begin']
        token[:end] = p['span']['end']
        
        # as the token appears in the text
        token[:lex] = sentence[token[:beg]..token[:end]-1]
        token[:pos] = p['obj'] # or is it token[:cat]?
        
        # so this is a big cheat
        token[:cat] = p['obj'][0..1]

        # update mapping
        spacy_token_ids[p['id']] = i
        tokens << token        
      end
      
      # just treat every dependency as if it was
      # an predicate-argument relation
      parsed['relations'].each do |r|
        # what is the token in question?
        i = spacy_token_ids[r['obj']]
        # i = spacy_token_ids[r['subj']]
        
        # change this to show dependency type
        tokens[i][:args] ||= [] 
        argument_counter = "ARG" + (tokens[i][:args].size + 1).to_s
        
        # if the token is the root, we set ARG1 => -1
        if r['pred'] == "ROOT"
          argument_token = -1
          root = i
        else
          argument_token = spacy_token_ids[r['subj']]
          # argument_token = spacy_token_ids[r['obj']]

        end   
        tokens[i][:type] = r['pred']  

        tokens[i][:args] << [ argument_counter , argument_token ]      
      end

      [tokens, root]
    else
      raise "Enju CGI server dose not respond."
    end
  end
  
  def get_base_noun_chunks(tokens)    
    base_noun_chunks = []
    
    within_noun_chunk = false    
    tokens.each_with_index do |token, i|
      # the first element in a noun chunk
      if NC_CAT.include?(token[:cat]) && 
         !within_noun_chunk
        
        within_noun_chunk = true
        base_noun_chunks << { :beg => i}
      
      # special case: possesive 's
      # only accept if the next token is a NN
      elsif POSSESIVE_TAGS.include?(token[:cat]) &&
            i+1 <= tokens.length &&
            NC_CAT.include?(tokens[i+1][:cat])
       
        next
      end
      
      # element after the last element of noun chunk  
      if !NC_CAT.include?(token[:cat]) && 
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

  # It finds the shortest path between the head word of any two base noun chunks that are not interfered by other base noun chunks.
  def get_relations (tokens, base_noun_chunks)
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
    rels
  end


  # It returns the index of the "focus word."  For example, for the input
  # 
  # What devices are used to treat heart failure?
  #
  # ...it will return 1 (devides).
  def get_focus (tokens, base_noun_chunks)
    puts '==================='
    # find the wh-word
    # assumption: one query has one wh-word
    wh = -1
    tokens.each do |t|
      if WH_CAT.include?(t[:cat])
        wh = t[:idx]
        break
      end
    end
    
    puts 'wh is: ', wh

    # focus = if wh > -1
    #           if tokens[wh][:args]
    #             tokens[wh][:args][0][1]
    #           else
    #             wh
    #           end
    #         elsif base_noun_chunks.nil? || base_noun_chunks.empty?
    #           nil
    #         else
    #           base_noun_chunks[0][:head]
    #         end
    # !focus && focus = -1
    puts 'base noun chunks: ', base_noun_chunks
    focus = if wh > -1
              if tokens[wh][:args]
                tokens[wh][:args][0][1]
              else
                wh
              end
            elsif base_noun_chunks.any?
              puts 'im here'
              base_noun_chunks[0][:head]
            else
              -1
            end    
    puts 'focus is: ', focus
    focus
  end

end

# From the Ruby documentation:
# __FILE__ is the magic variable that contains the name of the current file. 
# $0 is the name of the file used to start the program. This check says “If 
# this is the main file being used…” This allows a file to be used as a 
# library, and not to execute code in that context, but if the file is 
# being used as an executable, then execute that code.

if __FILE__ == $0
  parser = EnjuAccess::CGIAccessor.new("http://bionlp.dbcls.jp/enju")
  parse  = parser.parse("what genes are related to alzheimer?")
  # p parse
  # exit
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

#!/usr/bin/env ruby

# require 'rest-client'
require_relative '../accessors/accessor'

class Accessor::EnjuAccessor < Accessor
  attr_reader :enju

  def initialize(parser_url)
    super(parser_url)
  end

  private

  # returns tokens and sentence root index
  def get_parse (sentence)
    return [[], nil] if sentence.nil? || sentence.strip.empty?
    sentence = sentence.strip

    response = @server.get :params => {:sentence=>sentence, :format=>'conll'}
    case response.code
    when 200             # 200 means success
      raise "Empty input." if response =~/^Empty line/

      tokens = []

      # response is a parsing result in CONLL format.
      response.split(/\r?\n/).each_with_index do |t, i|  # for each token analysis
        dat = t.split(/\t/, 7)
        token = Hash.new
        token[:idx]  = i - 1   # use 0-oriented index
        token[:lex]  = dat[1]
        token[:base] = dat[2]
        token[:pos]  = dat[3]
        token[:cat]  = dat[4]
        token[:type] = dat[5]
        token[:args] = dat[6].split.collect{|a| type, ref = a.split(':'); [type, ref.to_i - 1]} if dat[6]
        tokens << token  # '<<' is push operation
      end

      root = tokens.shift[:args][0][1]

      # get span offsets
      i = 0
      tokens.each do |t|
        i += 1 until sentence[i] !~ /[ \t\n]/
        t[:beg] = i
        t[:end] = i + t[:lex].length
        i = t[:end]
      end

      [tokens, root]
    else
      raise "Enju CGI server dose not respond."
    end
  end


  # It finds base noun chunks from the category pattern.
  # It assumes that the last word of a BNC is its head.
  def get_base_noun_chunks (tokens)
    base_noun_chunks = []
    beg = -1    ## the index of the begining token of the base noun chunk
    tokens.each do |t|
      beg = t[:idx] if beg < 0 && NOUN_CHUNK_TAGS.include?(t[:cat])
      beg = -1 unless NOUN_CHUNK_TAGS.include?(t[:cat])
      if beg >= 0
        if t[:args] == nil && NOUN_CHUNK_HEAD_TAGS.include?(t[:cat])
          base_noun_chunks << {:head => t[:idx], :beg => beg, :end => t[:idx]}
          beg = -1
        end
      end
    end
    base_noun_chunks
  end
end

# From the Ruby documentation:
# __FILE__ is the magic variable that contains the name of the current file. 
# $0 is the name of the file used to start the program. This check says “If 
# this is the main file being used…” This allows a file to be used as a 
# library, and not to execute code in that context, but if the file is 
# being used as an executable, then execute that code.

if __FILE__ == $0
  parser = Accessor::EnjuAccessor.new("http://bionlp.dbcls.jp/enju")
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

#!/usr/bin/env ruby
# evaluate the contents of a collection's Dublin Core records for QA purposes
# run this from command line

# all this does is reads through the DC XML you give it, parses out each element, and then lists each unique value assigned to that element in a list that it prints to standard output

require 'nokogiri'
require 'json'

case
when ARGV.length == 0
  puts "Usage: eval.rb [file]"
  exit
when ARGV.length > 1
  puts "Script will only evaluate first file provided"
end

input = ARGV[0]
values = Hash.new

Nokogiri::XML.parse(File.read(input)).xpath("/metadata/oai_dc:dc/*").each do |node|
  name = node.name
  unless values.has_key? name
    values[name] = Array.new()
  end
  values[name].push(node.text)
end

values.each do |k,v|
  vals = v.uniq
  puts "#{k}:\n---"
  vals.each do |val|
    puts val
  end
  puts "\n"
end

##
# Script to take whatever Heritage West DC records we have and map them to MODS for Islandora ingest.
#
# This is a basic framework, which I would then customize to account for the quirks of whichever
# institution's metadata I'm working on at any given point.

require 'nokogiri'
require 'json'

def get_file
  print "Dublin Core XML file: "
  fname = gets.chomp
  if File.exist?(fname)
    doc = Nokogiri::XML(File.read(fname))
    unless doc.errors.empty?
      doc.errors.each do |error|
        puts "#{fname} not well-formed: #{error}"
      end
      puts "Exiting."
      exit
    end
  else
    puts "#{fname} not found."
    fname = get_file
  end
  return fname
end

input = get_file

Nokogiri::XML.parse(File.read(input)).xpath("/metadata/oai_dc:dc").each_with_index do |node, i|

  # the identifiers on these are all over the place so we just number them in sequence and name the files that way
  id = i + 1
  output = "#{id.to_s.rjust(3,"0")}.xml"

  # open a new XML Builder
  builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
    xml.mods({
        'version' => '3.4',
        'xmlns' => 'http://www.loc.gov/mods/v3',
        'xmlns:xlink' => 'http://www.w3.org/1999/xlink',
        'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
        'xsi:schemaLocation' => 'http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-4.xsd'
    }) {
      # map titles, allowing for multiple titles in source XML
      # a cataloger determines which titles receive disambiguating attributes
      node.xpath("dc:title").each_with_index do |title, index|
        case index
        when 0
          xml.titleInfo {
            xml.title title.text
          }
        else
          xml.titleInfo(:type => 'alternative') {
            xml.title title.text
          }
        end
      end

      # map creators
      # customization for CoBNi: these aren't oral histories so we don't do the roles
      node.xpath("dc:creator").each do |creator|
        xml.name {
          xml.namePart creator.text.strip
        }
      end

      # map contributors; we assume the 'contributor' is in fact the interviewer
      node.xpath("dc:contributor").each do |contributor|
        xml.name {
          xml.namePart contributor.text.strip
          xml.role {
            xml.roleTerm(:type => 'code') {
              xml.text "ctb"
            }
            xml.roleTerm(:type => 'text') {
              xml.text "contributor"
            }
          }
        }
      end

      # map relations; usually this is "Heritage Colorado," whom we treat as a contributor to the object
      node.xpath("dc:relation").each do |relation|
        xml.name {
          xml.namePart relation.text.strip
          xml.role {
            xml.roleTerm(:type => 'code') {
              xml.text "ctb"
            }
            xml.roleTerm(:type => 'text') {
              xml.text "contributor"
            }
          }
        }
      end

      # map type to a MODS-appropriate typeOfResource ("sound recording")
      # (return 'nil' if no dc:type is present)
      case node.xpath("dc:type").text
      when "sound"
        xml.typeOfResource "sound recording"
      else
        nil
      end

      # map originInfo, allowing for multiple publishers and dates
      xml.originInfo {
        # handle publishers; each receives its own <publisher> element
        publishers = []
        node.xpath("dc:publisher").each do |publisher|
          publishers.push(publisher.text)
        end
        publishers.each do |publisher|
          xml.publisher publisher
        end

        # handle dates
        # in cases of multiple dates we assume the earlier date is creation and the later date is digitization
        dates = []
        node.xpath("dc:date").each do |date|
          dates.push(date.text)
        end
        dates.sort!
        xml.dateCreated dates[0]
        xml.dateCaptured dates[1]
      }

      # map language; just the code, no text representation
      xml.language {
        xml.languageTerm(:type => 'code', :authority => 'iso639-2b') {
          xml.text node.xpath("dc:language").text
        }
      }

      # This next bit of code builds our abstract and our physical description fields. I apologize for it, it's pretty gnarly.
      # We need to read dc:format and dc:description into the next few arrays because physical description metadata (extents, MIME types, etc.) are stored in both elements.
      extents = []
      mimetypes = []
      physdesc = []

      # map dc:format; anything that reads like a MIME type (/^\w+\/\w+$/) goes to mimetypes[], otherwise it goes to extents[] (dc:format being home to both file format and file size/duration)
      node.xpath("dc:format").each do |f|
        case f.text
        when /^\w+\/\w+$/
          mimetypes.push(f.text.strip)
        else
          extents.push(f.text.strip)
        end
      end

      # map dc:description
      # anything that looks even remotely like technical metadata gets mapped to one of our three physical description arrays; otherwise we treat it like a mods:abstract
      # It will be the cataloger's job to read through these mods:abstracts and figure out which ones are real and which ones need to be re-assigned to another MODS element
      node.xpath("dc:description").each do |description|
        case description.text
        when /^Length:/, /^File size:/
          extents.push(description.text.gsub(/^(\w|\s)+: /, "").strip)
        when /^Master file:/
          physdesc.push(description.text.gsub(/^(\w|\s)+: /, "").strip)
        when /^Computer hardware:/, /^Sound quality note:/
          physdesc.push(description.text.strip)
        when /^\w+\/\w+$/
          mimetypes.push(description.text.strip)
        else
          xml.abstract description.text.strip
        end
      end

      # Now we can finally construct our mods:physicalDescription elements. I am so sorry for all of this.
      xml.physicalDescription {
        extents.each do |extent|
          xml.extent extent
        end
        mimetypes.each do |mimetype|
          xml.internetMediaType mimetype
        end
        physdesc.each do |note|
          xml.note note
        end
      }

      # Map dc:subject and dc:coverage. I'm just mapping everything to mods:topic here, and leaving it up to catalogers to re-assign them to the proper subject types, and mark up the complex headings appropriately.
      subjects = []
      node.xpath("dc:coverage").each do |coverage|
        subjects.push(coverage.text.strip)
      end
      node.xpath("dc:subject").each do |subject|
        subjects.push(subject.text.strip)
      end
      if !subjects.empty?
        subjects.each do |subject|
          xml.subject {
            xml.topic subject
          }
        end
      end

      # going to take this metadata at its word that these are in the Internet Archive and call all those links relatedItems
      node.xpath("dc:identifier").each do |identifier|
        xml.relatedItem {
          xml.location {
            xml.url identifier.text.strip
          }
        }
      end

      # and here is our constructed local identifier
      xml.identifier(:type => 'local') {
        xml.text "cobni_#{id.to_s.rjust(3,"0")}"
      }

      # Map dc:rights. The gsub() is because some of them link out to external sources for more information; metadata shouldn't do that but I'm not going to argue for now.
      xml.accessCondition node.xpath("dc:rights").text.strip.gsub('www.', 'http://www.')
    }
  end

  # OK cool, write our MODS record to a new file, deleting any existing XML record that may exist with the same file name
  File.delete(output) if File.exist?(output)
  File.open(output, 'w') { |f| f.write(builder.to_xml) }
end

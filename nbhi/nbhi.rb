require 'nokogiri'
require 'json'

input = "nbhi.xml"

Nokogiri::XML.parse(File.read(input)).xpath("/metadata/oai_dc:dc").each do |node|
  id = ""
  node.xpath("dc:identifier").each do |identifier|
    if identifier.text.start_with?('http://dcbuilder.bcr.org')
      id << identifier.text.gsub("http://dcbuilder.bcr.org/streaming/index.cfm?filename=","")
    else
      nil
    end
  end
  output = "#{id}.xml"
  builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
    xml.mods({'version' => '3.4', 'xmlns' => 'http://www.loc.gov/mods/v3'}) {
      xml.titleInfo {
        xml.title node.xpath("dc:title").text
      }
      node.xpath("dc:creator").each do |creator|
        xml.name {
          xml.namePart creator.text
          xml.role {
            xml.roleTerm(:type => 'code') {
              xml.text "ive"
            }
            xml.roleTerm(:type => 'text') {
              xml.text "interviewee"
            }
          }
        }
      end
      node.xpath("dc:contributor").each do |contributor|
        xml.name {
          xml.namePart contributor.text.strip
        }
      end
      case node.xpath("dc:type").text
      when "sound"
        xml.typeOfResource "sound recording"
      else
        nil
      end
      xml.originInfo {
        publishers = []
        node.xpath("dc:publisher").each do |publisher|
          publishers.push(publisher.text)
        end
        publishers.uniq!.each do |publisher|
          xml.publisher publisher
        end
        dates = []
        node.xpath("dc:date").each do |date|
          dates.push(date.text)
        end
        dates.sort!
        xml.dateCreated dates[0]
        xml.dateCaptured dates[1]
      }
      xml.language {
        xml.languageTerm(:type => 'code', :authority => 'iso639-2b') {
          xml.text node.xpath("dc:language").text
        }
      }
      node.xpath("dc:description").each do |description|
        case description.text
        when /^Length:/, /^File size:/, /^Master file:/, /^Computer hardware:/, /^Sound quality note:/, /^\w+\/\w+$/
          xml.physicalDescription {
            case description.text
            when /^Length:/, /^File size:/
              xml.extent description.text.gsub(/^(\w|\s)+: /, "").strip
            when /^Master file:/
              xml.note description.text.gsub(/^(\w|\s)+: /, "").strip
            when /^Computer hardware:/, /^Sound quality note:/
              xml.note description.text.strip
            else
              xml.internetMediaType description.text
              # will need to manually edit other XML records to account for other file formats
              # (we're not putting multiple file formats on one record again)
            end
          }
        else
          xml.abstract description.text.strip
        end
      end
      subjects = []
      node.xpath("dc:coverage").each do |coverage|
        subjects.push(coverage.text.strip)
      end
      node.xpath("dc:subject").each do |subject|
        subjects.push(subject.text.strip)
      end
      if !subjects.empty?
        xml.subject {
          subjects.each do |subject|
            xml.topic subject
          end
        }
      end
      xml.identifier(:type => 'local') {
        xml.text id
      }
      # completing the hyperlink, fwiw
      xml.accessCondition node.xpath("dc:rights").text.strip.gsub('www.', 'http://www.')
    }
  end

  File.delete(output) if File.exist?(output)
  File.open(output, 'w') { |f| f.write(builder.to_xml) }
end

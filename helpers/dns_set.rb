#!/bin/env ruby
# == Synopsis 
# 
# Hooks this instance's IP with a dns name (using AwsDns). The IP used will
# be the private IP by default (since internally instances cannot access each other
# through public IP if they have public addressing).
# 
# == Usage 
# 
# ruby dns_set.rb 
#      -i | --dnsid DNS_DNSID
#      [ -u | --user DNS_USER ] (Default: ENV['DNS_USER'] )
#      [ -p | --password DNS_PASSWORD ] (Default: ENV['DNS_PASSWORD'] )
#      [ -a | --address ADDRESS ] The IP address to set for this DNS record. (Default: private) 
#      [ -h | --help ] 
# 

# Rdoc related
require 'optparse' 

require '/var/spool/ec2/meta-data.rb'
require '/var/spool/ec2/user-data.rb'

def usage(code=0)
  out = $0.split(' ')[0] + " usage: \n"
  out << "  -i | --dnsid DNSID (HostedZoneId:FQDN) \n"
  out << "  [ -u | --user DNS_USER ] (Default: ENV['DNS_USER'] ) \n"
  out << "  [ -p | --password DNS_PASSWORD ] (Default: ENV['DNS_PASSWORD'] ) \n"
  out << "  [ -a | --address ADDRESS ] The IP address to set for this DNS record (Default: EC2_LOCAL_IPV4) \n"
  out << "  [ -h | --help ]   "
  puts out
  Kernel.exit( code )
end

#Default options
options = { 
  :user => ENV['DNS_USER'],
  :password => ENV['DNS_PASSWORD']
}
opts = OptionParser.new 
opts.on("-h", "--help") { raise "Usage:" } 
opts.on("-i ", "--dnsid DNSID") {|str| options[:dnsid] = str } 
opts.on("-u ", "--user DNS_USER") {|str| options[:user] = str } 
opts.on("-p ", "--password DNS_PASS") {|str| options[:password] = str } 
opts.on("-a ", "--address ADDRESS") {|str| options[:address] = str }
begin
  opts.parse(ARGV) 
rescue Exception => e
  puts e 
  usage(-1) 
end

# Required options: DNSID
usage(-1) unless options[:dnsid] && options[:user] && options[:password]

#Instance's VPN Adress
vpn_cubed_ipv4=`/sbin/ifconfig|grep 'inet addr'|cut -d':' -f2|awk '{print $1}'|tail -1`
this_ip = (vpn_cubed_ipv4)
this_ip = options[:address] if options[:address]
if( this_ip.nil? || "#{this_ip}".empty? )
  puts "WARNING: cannot retrieve VPN_CUBED_IPV4 meta-data... using EC2_PUBLIC_IPV4 instead"
  unless ENV['EC2_PUBLIC_IPV4'].nil? && "#{ENV['EC2_PUBLIC_IPV4']}".empty?
    this_ip = ENV['EC2_PUBLIC_IPV4']
  else
    puts "ERROR: cannot retrieve EC2_PUBLIC_IPV$, either."
    exit(-1)
  end
end

zone_id,hostname=options[:dnsid].split(':')

auth=`dig  #{hostname} SOA +noall +authority | tail -1 | awk '{print $5}'`.chomp
current_ip= `dig +short #{hostname}`.chomp
current_ttl=`dig @#{auth} #{hostname} A +noall +answer | tail -1 | awk '{print $2}'`.chomp
aws_cred=<<EOF
%awsSecretAccessKeys = (
    "my-aws-account" => {
        id => "#{options[:user]}",
        key => "#{options[:password]}",
    },
);
EOF
secrets_filename="/root/.aws-secrets"
File.open(secrets_filename, "w") { |f| f.write aws_cred }
File.chmod(0600, secrets_filename)
endpoint="https://route53.amazonaws.com/2010-10-01/"
xml_doc = "https://route53.amazonaws.com/doc/2010-10-01/"

modify_cmd=<<EOF
<?xml version="1.0" encoding="UTF-8"?>
<ChangeResourceRecordSetsRequest xmlns="#{xml_doc}">
  <ChangeBatch>
    <Comment>
    Modified by RightScale
    </Comment>
    <Changes>
      <Change>
        <Action>DELETE</Action>
        <ResourceRecordSet>
          <Name>#{hostname}.</Name>
          <Type>A</Type>
          <TTL>#{current_ttl}</TTL>
          <ResourceRecords>
            <ResourceRecord>
              <Value>#{current_ip}</Value>
            </ResourceRecord>
          </ResourceRecords>
        </ResourceRecordSet>
      </Change>
      <Change>
        <Action>CREATE</Action>
        <ResourceRecordSet>
          <Name>#{hostname}.</Name>
          <Type>A</Type>
          <TTL>60</TTL>
          <ResourceRecords>
            <ResourceRecord>
              <Value>#{this_ip}</Value>
            </ResourceRecord>
          </ResourceRecords>
        </ResourceRecordSet>
      </Change>
    </Changes>
  </ChangeBatch>
</ChangeResourceRecordSetsRequest>
EOF
cmd_filename="/tmp/modify.xml"
File.open(cmd_filename, "w") { |f| f.write modify_cmd }

result = ""
# Simple retry loop, sometimes the DNS call will flake out..
5.times do
  result = `$RS_ATTACH_DIR/dnscurl.pl --keyfile #{secrets_filename} --keyname my-aws-account -- -X POST -H "Content-Type: text/xml; charset=UTF-8" --upload-file #{cmd_filename} #{endpoint}hostedzone/#{zone_id}/rrset`
  break unless result =~ /HttpFailure/
end

if(result =~ /ChangeResourceRecordSetsResponse/ ) then
  puts "DNSID #{options[:dnsid]} set to this instance IP: #{this_ip}"
else
  puts "Error setting the DNS, curl exited with code: #{$?}, output: #{result}"
  exit(-1)
end

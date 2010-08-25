#!/usr/bin/perl -w
use strict;
use Net::Interface;
use Data::Dumper;
use XML::Simple;
use LWP::Simple;
use IO::File;
use Net::SFTP::Foreign;
use Net::SFTP::Foreign::Constants qw(:flags);

#############################################################################
## CONFIGURATION
#############################################################################
my $this_host = "name_of_this_host";
my $ssh_host  = "name_of_remote_host";
my $ssh_user  = "your_user";
my $ssh_passw = "your_password";
my $ssh_file  = "/path/to/file/on/remote/host";
my $name_if   = "name_of_local_public_interface";
my $filename  = "local_file_there_will_keep_info_about_past transactions";
my $method = "url";         # maybe 'url' or 'interface'
my $get_ip_url = "http://www.whatismyip.com/automation/n09230945.asp";
#############################################################################

## Main section

my $addr = get_addr ($name_if, $method);
my ($fh_local, $old_ip, $success) = file_input($filename);
    
my $data = make_data($addr);
print "$addr 222 \n";
my $error;
if ($addr eq $old_ip) {
    if ($success eq "yes") {
        # that's right!
        undef $fh_local;
        exit 0;
    } else {
        $error = save_to_serv($data);
    }
} else {
    $error = save_to_serv($data);
}

if ($error) {
    save_data($fh_local, $data, "no");
    undef $fh_local;
} else {
    save_data($fh_local, $data, "yes");
    undef $fh_local;
}


## Subs

# conver binary IP address to the decimal form
sub bintoip {
    my $bin_ip= shift;
    my $hex_ip = unpack ('H*', $bin_ip);
    my $bytes_to_extract = 2;
    my $dec_ipi = "";
    
    for my $num_of_octet (1..4) {
        my $offset = 2*$num_of_octet;
        if ($num_of_octet == 4 and length($hex_ip) == 7) {
            # this acation is neeeded for the first octets in hex adderss
            $bytes_to_extract = 1;
            $offset = 7;
        }
        # we begin constructing ip-address with end 
        my $buf = substr $hex_ip, -$offset, $bytes_to_extract;
        $dec_ip = hex($buf) . "." . $dec_ip;
    }
    chop $dec_ip;
    return $dec_ip;
}

# get public IP by selected method
sub get_addr {
    my ($interface_name, $method_to_get) = @_;
    my $adrr;

    if ($method_to_get =~ /interface/) {
        my $if = Net::Interface->new($interface_name);
        my $binaddr = $if->address;
        $addr = bintoip($binaddr);
    } 
    elsif ($method_to_get =~ /url/) {
        $addr = get($get_ip_url);
        if (not defined $addr) {
            die "couldnrt get it! \n";
        }
    }
    return $addr;
}

# make data structure which will be translated into th XML
sub make_data {
    my $ip = shift;
    my $time = localtime;
    my $result_ref = {
        "ip" => "$ip",
        "date" => "$time",
        "success" => ""
    };
    return $result_ref;
}

# convert data to xml (and save) after writing data to the server 
sub form_xml {
    my ($data_to_save, $is_success) = @_;
    if ($is_success) {
        if ($is_success eq "yes") {
            $data_to_save->{"success"} = "yes";
        } else {
            $data_to_save->{"success"} = "";
        }
    } else {
        delete $data_to_save->{"success"};
    }
    my $xs = XML::Simple->new(Rootname => $this_host, XMLDecl => 1);
    my $xml_info = $xs->XMLout($data_to_save);
    return $xml_info;
}

# save transfered data on the local disk for the future cheking
sub save_data {
    my ($fh_save, $info, $is_success) = @_;
    
    $fh_save->open("> $filename");
    my $xml_info = form_xml($info, $is_success);
    print $fh_save "$xml_info";
    $fh_save->close;
}

# initialize file with saved procesed data
sub file_input {
    my $file_name = shift;
    my $fh_old_local = IO::File->new;
    $fh_old_local->open( $file_name );
    
    my @requested_params;
    if ( !-z $file_name ) {
        print "mark !!\n";
        my $info = XMLin($fh_old_local);
        @requested_params = ($info->{"ip"}, $info->{"success"});
    } else {
        @requested_params = ('fake_address');
    }
    $fh_old_local->close;
    return $fh_old_local, @requested_params;
}

# save formed in XML data the remote server
sub save_to_serv {
    my $info = shift;
    my %args = ("host" => "$ssh_host", "user" => "$ssh_user", "password" => "$ssh_passw");
    my $xml_data = form_xml($info);
    my $path = "$ssh_file";
    
    my $sftp = Net::SFTP::Foreign->new(%args, more => [-o => "StrictHostKeyChecking no"]);
    my $fh_remote = $sftp->open($path, SSH2_FXF_WRITE|SSH2_FXF_CREAT) 
        or return $sftp->error;
    $sftp->write($fh_remote, $xml_data);
    return;
}


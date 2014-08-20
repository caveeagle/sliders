#!/usr/bin/perl

use strict;
use Time::Local;
use Date::Parse;
use DBI;
use SDB::export;
use SDB::cgi;
use SDB::common;
use Data::Dumper;
use Crypt::CBC;
use GD;

use cave::_common qw($DB $HOST $USER $PASSWORD $LINEFILE_DIR $TRAVFILE_DIR $FONT_DIR $CACHE_DIR $cryptkey);

############################


##### Global variables #####
 
my @daylimit = (0,30,60,90,120,150,183,365,365*2,365*3,365*5,365*10,365*50);

my $nullviewstr = " 0 (дата достигнута)";

my $write_rlink = 0; # Write remoute link into DB

#### read query string parameters

my $query_string =  get_query_string();
my %cgi = parse_query_string( $query_string);

if((not defined($cgi{'real_decrypt_id'}))&&(not defined($cgi{'sid'})))
{
			print_content_type();
			print "Error - require parameter \"sid\" ";
			print STDERR "Error - require parameter \"sid\" \n\n";
			exit 0;
}	

my $id;
if(exists $cgi{'real_decrypt_id'})
{
	$id = $cgi{'real_decrypt_id'};
}
else
{
	my $crypted_block = $cgi{'sid'};
	my $cipher = new Crypt::CBC($cryptkey,'Blowfish');
	my $text_decrypt = $cipher->decrypt_hex($crypted_block);
    $id = $text_decrypt;
}


my $force = $cgi{'force'} ? $cgi{'force'} : 0 ;

##### Update access time

if($force==0)
{
	update_access_time($id);
}

##### Write remoute url

if($write_rlink)
{
	update_rlink($id);
}	

#####  Check my cache

my $cachfile = sprintf("%09d",$id);
$cachfile = $cachfile.".png";
$cachfile = $CACHE_DIR."/".$cachfile;

if((-e $cachfile)and($force==0))
{   
	### draw and exit ###
	get_file_in_web();
	exit 0;
}
### Get slider info:

my $info = get_info($id);

###############################
#                             #
# Count types:                #
#                             #
# 0 - ќсталось до даты	      #
# 1 - ѕрошло с даты           #
# 2 - —чЄтчик до дн€ года     #
#                             #
###############################
  
my $counttype = $info->{'slider_type'};

my $user_string = $info->{'userstring'} ? $info->{'userstring'} : "";

my $adv = ($info->{'acc_type'} == 2);

my($date_begin,$date_end,$date_day); # yyyy-mm-dd  ;  for date_day: mm-dd

if($counttype==0)
{
	$date_begin = $info->{'date_begin'};
	$date_end = $info->{'date_end'};
}
elsif($counttype==1)
{
	$date_begin = $info->{'date_begin'};
}
elsif($counttype==2)
{
	$date_day = $info->{'date_day'};
}

my ($percentage,$viewstr);

### Make string and calc percentage ###

calc_string();

##############################

#print STDERR "v=$viewstr\n";
#print STDERR "p=$percentage\n";

my $linefile = $LINEFILE_DIR."/".$info->{'linefile'};
my $travfile = $TRAVFILE_DIR."/".$info->{'travellerfile'};

my $advfile = "/www/docs/cave/slider/ad/ad.png";

### Draw and get file:

draw_file();

get_file_in_web();

exit 0;		



#######################################################
#######################################################
#######################################################


#######################################################
#                                                     #
#                  Subroutines                        #
#                                                     #
#######################################################


sub calc_string()
{
		############################################
		### Caclulate difference and make string ###
		############################################
		
		my ($curr_year,$curr_month,$curr_day) = (localtime)[5,4,3];
		$curr_month = $curr_month+1;
		$curr_year = $curr_year+1900;
		my $curr_time = time(); 
		
		my ($Dy,$Dm,$Dd);
		
		if($counttype == 2)
		{
		 # Calculate date begin-end from annual 	
		 my $t = str2time("$curr_year-$date_day");
		 
		 if($t<$curr_time)
		 {
		   $date_end = "".($curr_year+1)."-".$date_day; 
		 }
		 else
		 {
		   $date_end = "".$curr_year."-".$date_day; 
		 }
		
		}
		
		if(($counttype==0)||($counttype==2))
		{
		  my ($diff_year,$diff_month,$diff_day) = split('-',$date_end);
		  ($Dy,$Dm,$Dd) = Delta_YMD_My($curr_year,$curr_month,$curr_day,$diff_year,$diff_month,$diff_day);
		}
		elsif($counttype==1)
		{
		  my ($diff_year,$diff_month,$diff_day) = split('-',$date_begin);
		  ($Dy,$Dm,$Dd) = Delta_YMD_My($diff_year,$diff_month,$diff_day,$curr_year,$curr_month,$curr_day);
		}
		
		### Make string ###
		
		my $makeviewstr = make_string($Dy,$Dm,$Dd);
		$viewstr = $user_string.$makeviewstr;
		
		###################
		
		###########################
		#### Calculate percent ####
		###########################
		
		if($counttype==0)
		{
			my $time_end = str2time($date_end);
			my $time_begin = str2time($date_begin);
			$percentage = ($curr_time-$time_begin)/($time_end-$time_begin);
			if($time_end<$curr_time)
			{
				$percentage = 1;
				$viewstr = $user_string.$nullviewstr;
			}	
			
		}
		elsif($counttype==1)
		{
			my $time_begin = str2time($date_begin);
		    my $delta = ($curr_time-$time_begin)/86400; # in days
		
			my ($time_max,$time_min);
			for(my $i=1;$i<scalar(@daylimit);$i++)
			{
				$time_max = $daylimit[$i];
				$time_min = $daylimit[$i-1];
				
				if($time_max>$delta)
				{
					last;
				}	
			}
            
			$time_max = $time_begin+$time_max*86400;
			$time_min = $time_begin+$time_min*86400;
			$percentage = ($curr_time-$time_min)/($time_max-$time_min);
		}
		elsif($counttype==2)
		{
			my $time_end = str2time($date_end);
			$percentage = ($time_end-$curr_time)/(366*86400);
			$percentage = 1-$percentage;
		}	
		
		if($percentage>1){$percentage=1;}
		
		return;
}


sub Delta_YMD_My()
{
	my($y1,$m1,$d1,$y2,$m2,$d2) = (@_)[0,1,2,3,4,5];;
	
	my($Dd,$Dm,$Dy);

	$Dd = $d2-$d1;
	$Dm = $m2-$m1;
	$Dy = $y2-$y1;

	if(($Dm==0)&&($Dd<0))
	{
		$Dy = $Dy-1;
		$y1 = $y2;
	    $Dm = 12+$Dm;
	}

	if($Dm<0)
	{
		$Dy = $Dy-1;
		$y1 = $y2;
	    $Dm = 12+$Dm;
	}
	
	if($Dd<0)
	{
		$Dm = $Dm-1;
	
		my $cor = 0;
		if($d1>28)
		{
			$cor = 3;
			$d1=$d1-$cor;
		}
			
		my $tmon = ($m2-1)-1;
		
		my $time1;
		if($tmon>=0)
		{
			$time1 = timegm(0,0,0,$d1,$tmon,$y1-1900);
		}
		else
		{
			$time1 = timegm(0,0,0,$d1,11,$y1-1900-1);
		}

		###my $time2 = timegm(0,0,0,$d2,$m2-1,$y2-1900); # fix error 19.05.2008
		my $time2 = timegm(0,0,0,$d2,$m2-1,$y1-1900);
		
	    $Dd = ($time2-$time1)/86400;
	    $Dd = $Dd - $cor;
	}
	
	return ($Dy,$Dm,$Dd);
}

sub make_string()
{
		my ($Dy,$Dm,$Dd) = ($_[0],$_[1],$_[2]); 

		my $date_string = " ";
		
		if(($Dy==0)&&($Dm==0)&&($Dd==0))
		{
			$date_string = $date_string."меньше дн€";
			return $date_string;
		}	
		
		if($Dy!=0)
		{
		    my $str;
		    
			if($Dy==1)
			{
				$str="год";
			}	
			elsif($Dy>1&&$Dy<5)
			{
				$str="года";
			}	
			elsif($Dy>=5&&$Dy<21)
			{
				$str="лет";
			}
			elsif($Dy%10==1)
			{
				$str="год";
			}
			elsif(($Dy%10==2)||($Dy%10==3)||($Dy%10==4))
			{
				$str="года";
			}
		    else
			{
				$str="лет";
			}
		
			$date_string = $date_string."$Dy $str";
			
			if($Dm!=0&&$Dd!=0)
			{
				$date_string = $date_string.", ";
			}
			elsif($Dm==0&&$Dd==0)
			{
				$date_string = $date_string."";
			}
			else
			{
				$date_string = $date_string." и ";
			}
					
		}
		
		if($Dm!=0)
		{
		    my $str;
		    
			if($Dm==1)
			{
				$str="мес€ц";
			}	
			elsif($Dm>1&&$Dm<5)
			{
				$str="мес€ца";
			}	
			else
			{
				$str="мес€цев";
			}
			
		
			$date_string = $date_string."$Dm $str";
			
			if($Dd!=0)
			{
				$date_string = $date_string." и ";
			}
		}
		
		my $is_night = $info->{'day_night'} ? $info->{'day_night'} : 0;
		
		if($Dd!=0)
		{
		    my $str;
		    
			if($Dd==1)
			{
				if($is_night)
				{
					$str="ночь";
				}
				else
				{
					$str="день";
				}
			}	
			elsif($Dd>1&&$Dd<5)
			{
				if($is_night)
				{
					$str="ночи";
				}
				else
				{
					$str="дн€";
				}
			}	
			elsif($Dd>=5&&$Dd<21)
			{
				if($is_night)
				{
					$str="ночей";
				}
				else
				{
					$str="дней";
				}
			}
			elsif($Dd%10==1)
			{
				if($is_night)
				{
					$str="ночь";
				}
				else
				{
					$str="день";
				}
			}
			elsif(($Dd%10==2)||($Dd%10==3)||($Dd%10==4))
			{
				if($is_night)
				{
					$str="ночи";
				}
				else
				{
					$str="дн€";
				}
			}
		    else
			{
				if($is_night)
				{
					$str="ночей";
				}
				else
				{
					$str="дней";
				}
			}
		
			$date_string = $date_string."$Dd $str";
		}
		
		return $date_string;
}


sub get_info()
{
	my $id = @_[0];
	
	my $dbi = DBI->connect( "DBI:mysql:database=$DB;host=$HOST",$USER,$PASSWORD);
	
	my $select_command = "SELECT * from sliders WHERE ID=$id";
	
	my $sth = $dbi->prepare( $select_command );
	$sth->execute();
	my $href = $sth->fetchrow_hashref();
	
	if($sth->rows==0)
	{ 
		print STDERR "Error in DB - ID=$id not found!\n";
		exit; 
	}
	
	return $href;
}

sub update_access_time()
{
	my $id = @_[0];
	
	my $dbi = DBI->connect( "DBI:mysql:database=$DB;host=$HOST",$USER,$PASSWORD);
	
	my $command = "UPDATE sliders SET access_time=NOW() WHERE ID=$id";

	my $ret = $dbi->do($command);
	if(!(defined $ret))
	{
	 print STDERR "\ncommand failed $command\n\n";
	}
	
}

sub update_rlink()
{
	my $id = @_[0];
	
	my $dbi = DBI->connect( "DBI:mysql:database=$DB;host=$HOST",$USER,$PASSWORD);
	
	my $rlink = $ENV{'HTTP_REFERER'};
	
	if($rlink eq "") {$rlink="-";}
	
	my $command = "UPDATE sliders SET remoute_link=\'$rlink\' WHERE ID=$id";

	my $ret = $dbi->do($command);
	if(!(defined $ret))
	{
	 print STDERR "\ncommand failed $command\n\n";
	}
	
}

sub draw_file()
{
			
		################################################
		
		my $fontname = $FONT_DIR."/verdana.ttf";
		
		my $stringHeight = 12;
		
		################################################
		
		if(not(-e $linefile))
		{
			print_content_type();
			print "Error - not found file!";
			print STDERR "Errror - not found file $linefile\n";
			exit 0;
		}	

		if(not(-e $travfile))
		{
			print_content_type();
			print "Error - not found file!";
			print STDERR "Errror - not found file $travfile\n";
			exit 0;
		}	

		my $advim;
		my $advHeight;
		if(not(-e $advfile))
		{
			$adv=0;
		}
		else
		{
			$advim = GD::Image->newFromPng($advfile,1);
			$advHeight = $advim->height;
		}	 
		
		
		my $lineim = GD::Image->newFromPng($linefile,1); 
		my $travim = GD::Image->newFromPng($travfile,1); 

		my $imW = $lineim->width;
		my $imH = ($lineim->height)+$stringHeight;
		
		if($adv)
		{
			$imH = $imH+$advHeight;
			
			if($advim->width>$imW)
			{
				$imW = $advim->width;
			}	
		}	

		
		my $im = new GD::Image($imW,$imH,1);
		
		my ($back_red,$back_green,$back_blue) = split('-',($info->{'back_color'}));
		my $back_color = $im->colorAllocate($back_red,$back_green,$back_blue); 

		$im->filledRectangle(0,0,$imW-1,$imH-1,$back_color);
		
		my ($destX,$destY);
		
		if($adv)
		{
			$im->copy($lineim,0,$advHeight,0,0,$lineim->width,$lineim->height);
			
			$destX = int(($imW-($travim->width))*$percentage);
			$destY = int((($lineim->height)-($travim->height))/2)+$advHeight;
		}
        else
		{
			$im->copy($lineim,0,0,0,0,$lineim->width,$lineim->height);
			
			$destX = int(($imW-($travim->width))*$percentage);
			$destY = int((($lineim->height)-($travim->height))/2);
		}
        
		$im->copy($travim,$destX,$destY,0,0,$travim->width,$travim->height);
		
		if($adv)
		{
		    my $dX = int(($imW-($advim->width))/2);
		    
			$im->copy($advim,$dX,0,0,0,$advim->width,$advim->height);
		}
		
		
		my ($font_red,$font_green,$font_blue) = split('-',($info->{'string_color'}));
		
		my $fontcolor = $im->colorAllocate($font_red,$font_green,$font_blue); 
		
		my $fontsize = 8;
		
		$im->stringFT($fontcolor,$fontname,$fontsize,0,2,$imH-2,stringToDec($viewstr),{charmap=>'Unicode'});
		
		##$im->string(gdTinyFont,2,10,"“ест",$fontcolor);
		
		open(FH,">$cachfile") or die "error!";
		print FH ($im->png()) ;
		close(FH);
		
		return;
}


sub stringToDec
{ 
	my $ustring = ''; 
	for my $char (split //, shift)
	{ 
		if(ord($char)>127)
		{ 
			$ustring .= "&#" . (unpack("U", $char)+848) . ";"; 
		}
		else
		{ 
			$ustring .= $char; 
		} 
	} 
	return $ustring; 
}


sub get_file_in_web()
{
	my $png_data;
	my $filesize = -s $cachfile;
	
	open(FC,$cachfile);
	read(FC,$png_data,$filesize);
	close(FC);
	
	print_content_type("image/png");
	print $png_data;
}
 



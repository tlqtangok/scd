#!perl
# written by jidor at 2019-12-02
use strict ;
use feature qw(say);
use List::Util qw(first sum max shuffle maxstr);
#use List::MoreUtils qw(uniq);
#use File::Spec::Functions;
use File::Basename qw(dirname basename);
use Data::Dumper;
#use Scalar::Util qw/reftype/;
#use File::Copy;
#use File::Find;
use FindBin qw($Bin);
use File::Spec;
use File::Spec::Functions;

#use Cwd qw(abs_path);
use strict;
use threads;
use threads::shared;
use POSIX qw(assert); 
use MIME::Base64 qw( encode_base64 decode_base64);
#use Expect; 
#use Expect::Simple;  # sudo cpan -i Expect::Simple
use strict;
use arybase; # this is used to make sure exe can be run!!!
use feature qw(state);

#use Expect;
#
#

# cp $t/tor.PL $perl_p/tor.PL   &&   cp $t/tor.PL $perl_p/fr.PL
use strict ;
use feature qw(say);
use File::Basename qw(dirname basename);
#use List::Util qw(first sum max shuffle maxstr);
#use List::MoreUtils qw(uniq);
#use File::Spec::Functions;
use Data::Dumper;
#use Scalar::Util qw/reftype/;
#use File::Copy;
#use File::Find;
#use Cwd qw(abs_path);
use strict;

use threads;
use threads::shared;

use POSIX qw(assert); 
use MIME::Base64 qw(encode_base64 decode_base64);
#use Redis; 
use IO::Compress::Gzip qw(gzip $GzipError); 

use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use Archive::Tar;
use File::Find;
use File::Path;
use Cwd qw(abs_path cwd);
use File::Spec;
#use Try::Tiny;
use JSON; 
use Encode; 

use Digest::MD5;
use Digest::MD5 qw(md5_hex);
use Time::HiRes qw(gettimeofday);
#use URI::Escape;
#use utf8;
#use Term::ReadKey;
#use Term::ProgressBar;

#use Encode; 
#use UTF8; 
#binmode( STDIN,  ':encoding(utf8)' );
#binmode( STDOUT, ':encoding(utf8)' );   
#binmode( STDERR, ':encoding(utf8)' );   




##################
### global var ###
##################
my $fn_scd_config = "scd.config"; 
my $server = "localhost"; 
#my $server = join "", reverse qw(m o c . s r e o g l a);
my $server_port = "6379"; 
my $username = "$ENV{USER}"; 

&source_config_if_needed($fn_scd_config); 

my $R_ = "redis-cli -h $server -p $server_port"; 

my $slave_info_r0 = qx{hostname -I}; $slave_info_r0 =~ s/ .*$//g; chomp($slave_info_r0); 
$slave_info_r0 =  merge_u_ip($username, $slave_info_r0);


my $key_list_cluster_info_all = "cluster_info_all"; 
my $key_list_cluster_ans_all = "cluster_ans_all"; 
my @capture_cmd = ( 
    ["get" ,  "cluster_info",],
    ["set" ,  "cluster_task", "XXX",],
    ["rpush",  $key_list_cluster_ans_all, "XXX",],
); 

my $MAX_IP_ALLOW = 128;

##################


&main();


#main_
sub main()
{
    #my $fn_run_cluster_task_log = "run_cluster_task.log";  `rm $fn_run_cluster_task_log ` if -e $fn_run_cluster_task_log;
    # redis-cli -h algoers.com  set cluster_task 'date'

    $| = 1;
    &check_deps();

    &run_subtask_if_arg_meet(\@ARGV);

    &run_td_sync_cluster_info();

    &run_slave(); 

}


### sub list ###
sub run_slave()
{
    open my $FP , "$R_ monitor |"; 
    while(<$FP>)
    {
        chomp; 
        my $loc_s = index($_, q(")); 
        $_  = substr($_, $loc_s); 
        my (@arr_cmd) = $_ =~  m/\"(.*?)\"/g; 

        if ( "@arr_cmd[0..1]" eq "@{$capture_cmd[0]}[0..1]")
        {
            say "- get all cluster_info to list [$key_list_cluster_info_all] "; 
            &get_cluster_info(); 
        }
        elsif ( "@arr_cmd[0..1]" eq "@{$capture_cmd[1]}[0..1]" )
        {
            # redis-cli -h algoers.com set cluster_task '172.16.166.224:date'
            #say "- ok, @arr_cmd"; 
            my $task = $arr_cmd[-1];  $task =~ s|\s+$||;

            my $slave_info = &pick_one_idle_cluster_ip();


            if ($slave_info eq $slave_info_r0)
            {
                our $flag_task_finish : shared = 0;
                our @top_cpu : shared = ();
                our @top_mem : shared = ();

                my $ts = &get_timestamp(); 
                my $prompt = "- [$ts] [$slave_info] [$task]"; 
                if( $task ne "echo END_BATCH_CLUSTER_TASK" )
                {
                    say $prompt;
                }

                #my $prompt_to_submit = "[x] [$task]";  
                #qx{$R_ rpush $key_list_cluster_ans_all '$prompt_to_submit' };

                my $td_top_cpu_memory = threads->create( sub ($,$,$){ 

                        my $flag_task_finish_ref = shift; 
                        my $top_cpu_ref = shift; 
                        my $top_mem_ref = shift; 

                        open my $FP_top , "top -u $ENV{USER}  -b -d 2 | " or die "cannot open FP_top\n"; 

                        while($$flag_task_finish_ref != 1)
                        {
                            my $e_line = <$FP_top>; 
                            chomp ($e_line); 

                            if ( $e_line =~ m/Cpu.s/ )
                            { 
                                my ($cpu_percent_overview) = $e_line =~ m/:\s+(.*?) us/;
                                push @$top_cpu_ref, $cpu_percent_overview;
                            }
                            elsif ($e_line =~ m/KiB Mem/)
                            {
                                my ($mem_used) = $e_line =~ m/(\d+?) used/; 
                                push @$top_mem_ref, ($mem_used >> 10); # to MegaBytes
                            }
                        }

                        close $FP_top; 
                    }, 

                    \$flag_task_finish, 
                    \@top_cpu,
                    \@top_mem
                );  

                my $td_task = threads->create( sub ($,$,$){ 
                        my $flag_task_finish_ref = shift;
                        my $top_cpu_ref = shift; 
                        my $top_mem_ref = shift; 

                        my $cmd_run_task_bash = qq{ bash -c ' $task ' 2>&1 } ;  

                        qx{which ls}; # just wait for a while
                        my $t0 = time();
                        my @cmd_out = qx{ $cmd_run_task_bash } ;  
                        $$flag_task_finish_ref = 1;
                        my $t1 = time(); 


                        my $cost_second = $t1 - $t0; 

                        my %h = (); 
                        $h{ts} = $ts;
                        $h{ip} = $slave_info; 
                        $h{cmd} = $task; 
                        $h{output} = join "",@cmd_out;
                        $h{cost} = "${cost_second}s";

                        my $d_gap = 1; 
                        my $len_ = @$top_mem_ref;
                        for(my $i=0;$i<$len_; $i += $d_gap)
                        {
                            $h{cpu}[$i] = int $top_cpu_ref->[$i]; 
                            $h{mem}[$i] = $top_mem_ref->[$i]; 
                        }

                        my $run_log_all = decode_utf8( Dumper(encode_json(\%h)) );
                        my $sz_need =  length($run_log_all) - 1; 
                        $run_log_all = substr($run_log_all, 9, $sz_need - 9 - 2); 


                        my ($ts_only_date) = $ts =~ m/(^.*?)_/;
                        open my $FP_append_log, ">>", "run_cluster_task_${ts_only_date}.log";
                        #binmode($FP_append_log);  

                        say $FP_append_log $run_log_all;
                        close $FP_append_log; 

                        qx{$R_ rpush $key_list_cluster_ans_all '$task' };

                        # clean list cluster ips if too long
                        my $get_len_of_ip_all = sub (){
                            my $len_of_ip_all = qx{$R_ llen $key_list_cluster_info_all};
                            my @arr_len_of_ip_all_ = split " ", $len_of_ip_all; 
                            my $len_of_ip_all_ = $arr_len_of_ip_all_[-1]; 
                            chomp($len_of_ip_all_); 
                            return $len_of_ip_all_;
                        };

                        my $len_of_ip_all_ = $get_len_of_ip_all->();
                        if ( $len_of_ip_all_ > $MAX_IP_ALLOW )
                        {
                            my $rand_num = int(rand(4)) + 2;
                            sleep $rand_num; 
                            my $len_of_ip_all_ = $get_len_of_ip_all->();
                            if ($len_of_ip_all_ > $MAX_IP_ALLOW)
                            {
                                qx{$R_ del $key_list_cluster_info_all };
                            }
                        }

                    }, 
                    \$flag_task_finish,
                    \@top_cpu,
                    \@top_mem
                );  


                $td_top_cpu_memory->detach();
                $td_task->detach();

            }
        }
    }
    close $FP; 
}

sub td_submit_get_all_cluster_ans()
{
    my $td_get_cluster_ans = threads->create
    (
        sub() {
            qx{$R_ del $key_list_cluster_ans_all};

            open my $FP_pipe, "$R_ monitor |" or die "- cannot open monitor pipe\n"; 

            my $ts = &get_timestamp();  
            my ($ts_only_date) = $ts =~ m/(^.*?)_/;
            open my $FP_append_log, ">>", "run_cluster_task_all_${ts_only_date}.log" or die "- cannot open file log!\n";

            my $flag_end_submit_batch = 0; 

            my $save_start = 0; 

            while(<$FP_pipe>)
            {

                my $loc_s = index($_, q(")); 
                $_  = substr($_, $loc_s); 
                my (@arr_cmd) = $_ =~  m/\"(.*?)\"/g; 

                if ( "@arr_cmd[0..1]" eq "@{$capture_cmd[2]}[0..1]" )
                {
                    my @ans_from_cluster = qx{$R_ lrange $key_list_cluster_ans_all $save_start -1};

                    $save_start += @ans_from_cluster;
                    #qx{$R_ ltrim $key_list_cluster_ans_all $save_start -1 };
                    chomp(@ans_from_cluster);
                    #sleep 1;
                    for my $e (@ans_from_cluster)
                    {
                        chomp($e);
                        if ($e =~ m/^\[x\]/)
                        {
                            if ($e =~ m/echo END_BATCH_CLUSTER_TASK/)
                            {
                                $flag_end_submit_batch = 1; 
                                sleep 1; 
                                last;
                            }
                            else
                            {
                                say "- $e"; 
                            }
                        }
                        elsif ($e =~ m/^\{/)
                        {
                            say $FP_append_log $e;
                        }
                    }


                    if ($flag_end_submit_batch == 1)
                    {
                        exit 0; 
                    } 
                }

            }
            close $FP_pipe; 
        }
    );

    return $td_get_cluster_ans;
}

sub merge_u_ip($ $)
{
    my ($u, $i) = @_; 
    return $u.'@'.$i; 
}

sub run_td_sync_cluster_info()
{
    my $td_sync_cluster_info = threads->create(
        sub ()
        {
            state $cnt_sync_cluster_info = 0; 
            while(1)
            {
                &get_cluster_info(); 
                my $rand_num = int(rand(100));
                my $sleep_seconds = 4; 
                #my $sleep_seconds = 4 + ($rand_num % 3); 

                $cnt_sync_cluster_info++; 
                if ($cnt_sync_cluster_info > $MAX_IP_ALLOW * 100)
                {
                    my $rand_num = int(rand(4)) + 2;
                    sleep $rand_num;
                    qx{$R_ del $key_list_cluster_info_all };
                }
                sleep $sleep_seconds;  
            }
        }
    );

    $td_sync_cluster_info->detach(); 
    return $td_sync_cluster_info;


}
sub check_deps()
{
    # 1. check program instance number
    my $prog_name = $0; 
    if ($prog_name =~ m/slave|submit/)
    {
        my $cmd_run_this_instance = "pgrep -f $prog_name -al"; 
        my @ans_ = qx{$cmd_run_this_instance}; 
        if ( @ans_ >= 2 )
        {
            $prog_name =~ s/\.PL//; 
            &assert_use_die(0==1, "- already run [$prog_name] on this machine ! \n"); 
        }
    }
    # 2. check if has redis-cli
    if ( qx{which redis-cli} eq "" )
    {
        &assert_use_die(0==1, "- please run [sudo apt install redis-server] to install redis-cli.\n"); 
    }

    # 3. check other utils
    my @arr_utils = qw(hostname pgrep top cat ls); 
    map
    {
        if (qx{which $_} eq "") 
        {
            &assert_use_die(0==1, "- please make sure your OS has [$_].\n"); 
        }
    }@arr_utils;
}

sub assert_use_die($, $)
{
	my $equ_or_not = shift; 
	my $die_msg = shift; 
	die $die_msg if not $equ_or_not; 
}

sub source_config_if_needed($)
{
	my $fn_config = shift; 
	my $SCRIPT_ROOT = $Bin;
	my $fn_config_full = catfile($SCRIPT_ROOT, $fn_config); 

	if (-f $fn_config_full) 
    {
        open my $fp_config, "<", $fn_config_full or die "- cannot open $fn_config_full !\n"; 
        
        my @fc = <$fp_config>;
        my $res = 0;
        $res = eval("@fc");
        if (defined $res){} else { &assert_use_die(0==1,  "- config file $fn_config_full has syntax error");}
        close $fp_config; 	
    }
}

sub run_subtask_if_arg_meet()
{
    my $argv_ref = shift; 
        if ($0 =~  m/submit/) 
        {

            qx{$R_ del $key_list_cluster_ans_all};

            #$td_get_cluster_ans->detach(); 
            my $job_cnt = 0; 

            if (@$argv_ref)
            {

                for(@$argv_ref)
                {
                    qx{ $R_ set cluster_task '$_'  };
                    $job_cnt++; 
                }

            }
            else
            {
                #$td_get_cluster_ans->detach(); 
                while(<>)
                {
                    chomp; 
                    if ($_ eq "quit" 
                        || $_ eq "q"
                        || $_ eq "exit")
                    {
                        
                        last; 
                    }
                    else
                    {
                        qx{ $R_  set cluster_task '$_' };
                        $job_cnt++; 
                    }
                }
            }

            say "- exit ...";
            my $ts = &get_timestamp();  
            my ($ts_only_date) = $ts =~ m/(^.*?)_/;

            while(1)
            {
                my @ans_from_cluster = qx{$R_ lrange $key_list_cluster_ans_all 0 -1};
                #say @ans_from_cluster; 

                if (@ans_from_cluster+0 == $job_cnt )
                {
                    qx{ rm -rf run_cluster_task_all_${ts_only_date}.log };
                    open my $FP_append_log, ">>", "run_cluster_task_all_${ts_only_date}.log" or die "- cannot open file log!\n";
                    print $FP_append_log join "", @ans_from_cluster;
                    close $FP_append_log; 

                    qx{$R_ del $key_list_cluster_ans_all};
                    say "- log file run_cluster_task_all_${ts_only_date}.log save successfully !\n"; 
                    last;
                }

                sleep 2;
            }

            exit 0; 
        }
}

sub get_cluster_info()
{
    #say "- ok, @arr_cmd"; 
    my $rand_num = int(rand(100));
    $rand_num = &add_zero_if_lt_10($rand_num); 
    my $slave_info = $slave_info_r0; 

    #say "- get all cluster_info to list [$key_list_cluster_info_all] "; 
    #`redis-cli -h $server del $key_list_cluster_info_all`;
    qx{$R_ rpush $key_list_cluster_info_all $rand_num:$slave_info};
}

sub pick_one_idle_cluster_ip()
{
    #&get_cluster_info();  
    my @value_ip_all = qx{$R_ lrange $key_list_cluster_info_all 0 -1}; 
    chomp(@value_ip_all); 

    my $sort_f = sub ($e){
        my @arr=split m/\:/, $_[0];
        return int $arr[0];
    }; 

    my %h = ();
    my %h_cnt = (); 
    my $exist_cnt = 0; 
    for my $e (reverse @value_ip_all)
    {
        my ($v, $ip_) = split m/\:/, $e;

        if (exists $h{$ip_})
        {
            $exist_cnt++;  
        }
        else
        {
            $h{$ip_} = $e;  
        }

        if ($exist_cnt == 2 * 2)
        {
            last;  
        }
    }

    @value_ip_all = values %h; 
    @value_ip_all = sort { $sort_f->($a) <=> $sort_f->($b) } @value_ip_all; 

    my $idx = 0; 
    state $cnt_idx_to_pick = 0; 
    if (@value_ip_all > 1)
    {
        $idx = $cnt_idx_to_pick % 2; 
    }
    $cnt_idx_to_pick++; 

    return (split m/\:/, $value_ip_all[$idx])[1]; 
}

sub add_zero_if_lt_10($num)
{
    my $num = shift @_;
    if ($num >=10 ){
        return "$num"
    }
    return "0$num";
}

sub get_timestamp()
{
	my $time_stamp = "NULL";
	my ($second, $minute, $hour, $date, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();
	# 17 16 20 24 7 116 3 236 1
	# 2016-08-24 20:16

	my $year = 1900 + $yearOffset;
	$month = $month + 1 ;
	$month = &add_zero_if_lt_10($month);
	$date = &add_zero_if_lt_10($date);
	$hour = &add_zero_if_lt_10($hour);
	$minute = &add_zero_if_lt_10($minute);
    $second = &add_zero_if_lt_10($second);
	$time_stamp = "$year$month${date}_${hour}${minute}_${second}";

	chomp( $time_stamp );
	return $time_stamp;
}


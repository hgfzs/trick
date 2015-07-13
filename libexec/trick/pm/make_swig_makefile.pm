package make_swig_makefile ;

use Exporter ();
use trick_version ;
use File::Path ;

@ISA = qw(Exporter);
@EXPORT = qw(make_swig_makefile);

use lib $ENV{"TRICK_HOME"} . "/bin/pm" ;
use File::Basename ;
use gte ; 
use trick_print ;
use Cwd ;
use Cwd 'abs_path';
use Digest::MD5 qw(md5_hex) ;
use strict ;

sub make_swig_makefile($$$) {

    my ($h_ref , $sim_ref , $make_cwd ) = @_ ;
    my ($n , $f , $k , $m);
    my (%all_icg_depends) = %{$$sim_ref{all_icg_depends}} ;
    my %temp_hash ;
    my @all_h_files ;
    my (@temp_array , @temp_array2) ;
    my ($ii) ;
    my ($swig_sim_dir, $swig_src_dir) ;
    my (%py_module_map) ;
    my @exclude_dirs ;
    my @swig_exclude_dirs ;

    my (@include_paths) ;
    my (@s_inc_paths) ;
    my (@defines) ;
    my ($version, $thread, $year) ;
    my $s_source_full_path = abs_path("S_source.hh") ;
    my $s_source_md5 = md5_hex($s_source_full_path) ;

    ($version, $thread) = get_trick_version() ;
    ($year) = $version =~ /^(\d+)/ ;
    (my $cc = gte("TRICK_CC")) =~ s/\n// ;
    @include_paths = $ENV{"TRICK_CFLAGS"} =~ /(-I\s*\S+)/g ; # get include paths from TRICK_CFLAGS
    push @include_paths , ("-I".$ENV{"TRICK_HOME"}."/trick_source" , "-I../include") ;

    @exclude_dirs = split /:/ , $ENV{"TRICK_EXCLUDE"};
    # See if there are any elements in the exclude_dirs array
    if (scalar @exclude_dirs) {
        @exclude_dirs = sort(@exclude_dirs );
        # Error check - delete any element that is null
        # (note: sort forced all blank names to front of array
        @exclude_dirs = map { s/(^\s+|\s+$)//g ; $_ } @exclude_dirs ;
        while ( not length @exclude_dirs[0] ) {
            # Delete an element from the left side of an array (element zero)
            shift @exclude_dirs ;
        }
        @exclude_dirs = map { (-e $_) ? abs_path($_) : $_ } @exclude_dirs ;
    }

    @swig_exclude_dirs = split /:/ , $ENV{"TRICK_SWIG_EXCLUDE"};
    # See if there are any elements in the swig_exclude_dirs array
    if (scalar @swig_exclude_dirs) {
        @swig_exclude_dirs = sort(@swig_exclude_dirs );
        # Error check - delete any element that is null
        # (note: sort forced all blank names to front of array
        @swig_exclude_dirs = map { s/(^\s+|\s+$)//g ; $_ } @swig_exclude_dirs ;
        while ( not length @swig_exclude_dirs[0] ) {
            # Delete an element from the left side of an array (element zero)
            shift @swig_exclude_dirs ;
        }
        @swig_exclude_dirs = map { (-e $_) ? abs_path($_) : $_ } @swig_exclude_dirs ;
    }

    # If there were no directories listed in TRICK_SWIG_EXCLUDE then copy the ones from ICG_EXCLUDE.
    if ( scalar @swig_exclude_dirs == 0 ) {
        @swig_exclude_dirs = split /:/ , $ENV{"TRICK_ICG_EXCLUDE"};
        # See if there are any elements in the swig_exclude_dirs array
        if (scalar @swig_exclude_dirs) {
            @swig_exclude_dirs = sort(@swig_exclude_dirs );
            # Error check - delete any element that is null
            # (note: sort forced all blank names to front of array
            @swig_exclude_dirs = map { s/(^\s+|\s+$)//g ; $_ } @swig_exclude_dirs ;
            while ( not length @swig_exclude_dirs[0] ) {
                # Delete an element from the left side of an array (element zero)
                shift @swig_exclude_dirs ;
            }
            @swig_exclude_dirs = map { (-e $_) ? abs_path($_) : $_ } @swig_exclude_dirs ;
        }
    }

    @defines = $ENV{"TRICK_CFLAGS"} =~ /(-D\S+)/g ;       # get defines from TRICK_CFLAGS
    push @defines , "-DTRICK_VER=$year" ;
    push @defines , "-DSWIG" ;

    @s_inc_paths = $ENV{"TRICK_SFLAGS"} =~ /-I\s*(\S+)/g ;     # get include paths from TRICK_CFLAGS

    # make a list of all the header files required by this sim
    foreach $n ( @$h_ref ) {
        push @all_h_files , $n ;
        foreach $k ( keys %{$all_icg_depends{$n}} ) {
            push @all_h_files , $k ;
            push @all_h_files , @{$all_icg_depends{$n}{$k}} ;
        }
    }

    # remove duplicate elements
    undef %temp_hash ;
    @all_h_files = grep ++$temp_hash{$_} < 2, @all_h_files ;
    @all_h_files = sort (grep !/trick_source/ , @all_h_files) ;

    $swig_sim_dir = "\$(CURDIR)/trick" ;
    $swig_src_dir = "\$(CURDIR)/build" ;

    # create output directories if they don't exist
    if ( ! -e "trick" ) {
        mkdir "trick", 0775 ;
    }
    if ( ! -e "build" ) {
        mkdir "build", 0775 ;
    }

    undef @temp_array2 ;
    foreach $n (sort @$h_ref) {
        if ( $n !~ /trick_source/ ) {
            undef @temp_array ;
            if ( !exists  $all_icg_depends{$n}{$n} ) {
                @temp_array = ($n) ;
            }
            push @temp_array , keys %{$all_icg_depends{$n}} ;
            @temp_array = grep !/\/trick_source\// , @temp_array ;
            @temp_array = grep !/C$/ , @temp_array ;

            # check to see if the parent directory of each file is writable.
            # If it isn't, then don't add it to the list of files to requiring ICG
            foreach my $f ( @temp_array ) {
                $f = abs_path(dirname($f)) . "/" . basename($f) ;
                if (exists $$sim_ref{icg_no}{$f}) {
                    trick_print($$sim_ref{fh}, "CP(swig) skipping $f (ICG No found)\n" , "normal_yellow" , $$sim_ref{args}{v}) ;
                    next ;
                }
                my ($continue) = 1 ;
                foreach my $ie ( @swig_exclude_dirs ) {
                    # if file location begins with $ie (an IGC exclude dir)
                    if ( $f =~ /^\Q$ie/ ) {
                        trick_print($$sim_ref{fh}, "CP(swig) skipping $f (ICG exclude dir $ie)\n" , "normal_yellow" , $$sim_ref{args}{v}) ;
                        $continue = 0 ;
                        last ;  # break out of loop
                    }
                }
                next if ( $continue == 0 ) ;
                my $temp_str ;
                $temp_str = dirname($f) ;
                $temp_str =~ s/\/include$// ;
                if ( -w $temp_str ) {
                    push @temp_array2 , $f ;
                }
            }
        }
    }

    undef %temp_hash ;
    @temp_array2 = grep ++$temp_hash{$_} < 2, @temp_array2 ;

    # Get the list header files from the compiler to compare to what get_headers processed.
    open FILE_LIST, "$cc -MM -DSWIG @include_paths @defines S_source.hh |" ;
    my $dir ;
    $dir = dirname($s_source_full_path) ;
    while ( <FILE_LIST> ) {
        next if ( /^#/ or /^\s+\\/ ) ;
        my $word ;
        foreach $word ( split ) {
            next if ( $word eq "\\" or $word =~ /o:/ ) ;
            if ( $word !~ /^\// and $dir ne "\/" ) {
                $word = "$dir/$word" ;
            }
            $word = abs_path(dirname($word)) . "/" . basename($word) ;
            # filter out system headers that are missed by the compiler -MM flag
            next if ( $word =~ /^\/usr\/include/) ;
            #print "gcc found $word\n" ;
            $$sim_ref{gcc_all_includes}{$word} = 1 ;
        }
    }

    # Only use header files that the compiler says are included.
    undef %temp_hash ;
    foreach my $k ( @temp_array2 ) {
        if ( exists $$sim_ref{gcc_all_includes}{$k} and
             $k !~ /$ENV{TRICK_HOME}\/trick_source/ ) {
            $temp_hash{$k} = 1 ;
        }
    }
    @temp_array2 = sort keys %temp_hash ;
    #print map { "$_\n" } @temp_array2 ;

    # remove headers found in trick_source and ${TRICK_HOME}/include/trick
    @temp_array2 = sort (grep !/$ENV{"TRICK_HOME"}\/include\/trick\// , @temp_array2) ;

    open MAKEFILE , ">build/Makefile_swig" or return ;
    open LINK_PY_OBJS , ">build/link_py_objs" or return ;
    print LINK_PY_OBJS "build/init_swig_modules.o\n" ;
    print LINK_PY_OBJS "build/py_top.o\n" ;

    print MAKEFILE "\
# SWIG rule
SWIG_FLAGS =
SWIG_CFLAGS := -I../include \${PYTHON_INCLUDES} -Wno-shadow -Wno-missing-field-initializers
ifeq (\$(IS_CC_CLANG), 1)
 SWIG_CFLAGS += -Wno-self-assign -Wno-sometimes-uninitialized
endif

ifdef TRICK_VERBOSE_BUILD
PRINT_SWIG =
PRINT_COMPILE_SWIG =
PRINT_SWIG_INC_LINK =
PRINT_CONVERT_SWIG =
else
PRINT_SWIG = \@echo \"[34mSwig[0m \$(subst \$(CURDIR)/build,build,\$<)\"
PRINT_COMPILE_SWIG = \@echo \"[34mCompiling swig[0m \$(subst .o,.cpp,\$(subst \$(CURDIR)/build,build,\$@))\"
PRINT_SWIG_INC_LINK = \@echo \"[34mPartial linking[0m swig objects\"
PRINT_CONVERT_SWIG = \@echo \"[34mRunning convert_swig[0m\"
endif

SWIG_MODULE_OBJECTS = \$(LIB_DIR)/swig_python.o

SWIG_PY_OBJECTS =" ;

    foreach my $f ( @temp_array2 ) {
        my ($continue) = 1 ;
        foreach my $ie ( @exclude_dirs ) {
            # if file location begins with $ie (an IGC exclude dir)
            if ( $f =~ /^\Q$ie/ ) {
                $continue = 0 ;
                $ii++ ;
                last ;  # break out of loop
            }
        }
        next if ( $continue == 0 ) ;

        my ($swig_dir, $swig_object_dir , $swig_module_dir , $swig_file_only) ;
        my ($swig_f) = $f ;
        $swig_object_dir = dirname($f) ;
        ($swig_file_only) = ($f =~ /([^\/]*)(?:\.h|\.H|\.hh|\.h\+\+|\.hxx)$/) ;
        print MAKEFILE" \\\n \$(CURDIR)/build$swig_object_dir/py_${swig_file_only}.o" ;
    }
    print MAKEFILE "\\\n $swig_src_dir/init_swig_modules.o" ;
    print MAKEFILE "\\\n $swig_src_dir/py_top.o\n\n" ;

    print MAKEFILE "convert_swig:\n" ;
    print MAKEFILE "\t\$(PRINT_CONVERT_SWIG)\n" ;
    print MAKEFILE "\t\$(ECHO_CMD)\${TRICK_HOME}/\$(LIBEXEC)/trick/convert_swig \${TRICK_CONVERT_SWIG_FLAGS} S_source.hh\n" ;
    print MAKEFILE "\n\n" ;

    my %swig_dirs ;
    my %python_modules ;
    $ii = 0 ;
    foreach my $f ( @temp_array2 ) {

        my ($swig_dir, $swig_object_dir , $swig_module_dir , $swig_file_only) ;
        my ($swig_f) = $f ;

        if ( $$sim_ref{python_module}{$f} ne "" ) {
            #print "[31mpython module for $f = $$sim_ref{python_module}{$f}[0m\n" ;
            my ($temp_str) = $$sim_ref{python_module}{$f} ;
            $temp_str =~ s/\./\//g ;
            $swig_module_dir = "$temp_str/" ;
            $temp_str =~ $$sim_ref{python_module}{$f} ;
            $temp_str =~ s/\\/\./g ;
            push @{$python_modules{$temp_str}} , $f ;
        } else {
            $swig_module_dir = "" ;
            push @{$python_modules{"root"}} , $f ;
        }

        my ($continue) = 1 ;
        foreach my $ie ( @exclude_dirs ) {
            # if file location begins with $ie (an IGC exclude dir)
            if ( $f =~ /^\Q$ie/ ) {
                $continue = 0 ;
                $ii++ ;
                last ;  # break out of loop
            }
        }
        next if ( $continue == 0 ) ;

        my $md5_sum = md5_hex($f) ;
        # check if .sm file was accidentally ##included instead of #included
        if ( rindex($swig_f,".sm") != -1 ) {
           trick_print($$sim_ref{fh}, "\nError: $swig_f should be in a #include not a ##include  \n\n", "title_red", $$sim_ref{args}{v}) ;
           exit -1 ;
        }
        $swig_f =~ s/([^\/]*)(?:\.h|\.H|\.hh|\.h\+\+|\.hxx)$/$1.i/ ;
        $swig_file_only = $1 ;
        my $link_py_obj = "build" . dirname($swig_f) . "/py_${swig_file_only}.o";
        $swig_f = "\$(CURDIR)/build" . $swig_f ;
        $swig_dir = dirname($swig_f) ;
        $swig_object_dir = dirname($swig_f) ;
        $swig_dirs{$swig_dir} = 1 ;

        print MAKEFILE "$swig_object_dir/py_${swig_file_only}.o : $swig_f\n" ;
        print MAKEFILE "\t\$(PRINT_SWIG)\n" ;
        print MAKEFILE "\t\$(ECHO_CMD)\$(SWIG) \$(TRICK_INCLUDE) \$(TRICK_DEFINES) \$(TRICK_VERSIONS) \$(SWIG_FLAGS) -c++ -python -includeall -ignoremissing -w201,303,362,389,401,451 -outdir trick -o $swig_dir/py_${swig_file_only}.cpp \$<\n" ;
        print MAKEFILE "\t\$(PRINT_COMPILE_SWIG)\n" ;
        print MAKEFILE "\t\$(ECHO_CMD)\$(TRICK_CPPC) \$(TRICK_CXXFLAGS) \$(TRICK_IO_CXXFLAGS) \$(SWIG_CFLAGS) -c $swig_dir/py_${swig_file_only}.cpp -o \$@\n\n" ;
        print LINK_PY_OBJS "$link_py_obj\n" ;

        $ii++ ;
    }

    foreach $m ( keys %python_modules ) {
        next if ( $m eq "root") ;
        my ($temp_str) = $m ;
        $temp_str =~ s/\./\//g ;
        print MAKEFILE "$swig_sim_dir/$m:\n" ;
        print MAKEFILE "\tmkdir -p \$@\n\n" ;
    }

    my $wd = abs_path(cwd()) ;

    print MAKEFILE "
\$(SWIG_MODULE_OBJECTS) : TRICK_CXXFLAGS += -Wno-unused-parameter -Wno-redundant-decls

\$(S_MAIN): \$(SWIG_MODULE_OBJECTS)

\$(SWIG_MODULE_OBJECTS) : \$(SWIG_PY_OBJECTS) | \$(LIB_DIR)
\t\$(PRINT_SWIG_INC_LINK)
\t\$(ECHO_CMD)ld \$(LD_PARTIAL) -o \$\@ \$(LD_FILELIST)build/link_py_objs
\n\n" ;

    print MAKEFILE "$swig_src_dir/py_top.cpp : $swig_src_dir/top.i\n" ;
    print MAKEFILE "\t\$(PRINT_SWIG)\n" ;
    print MAKEFILE "\t\$(ECHO_CMD)\$(SWIG) \$(TRICK_INCLUDE) \$(TRICK_DEFINES) \$(TRICK_VERSIONS) -c++ -python -includeall -ignoremissing -w201,303,362,389,401,451 -outdir $swig_sim_dir -o \$@ \$<\n\n" ;

    print MAKEFILE "$swig_src_dir/py_top.o : $swig_src_dir/py_top.cpp\n" ;
    print MAKEFILE "\t\$(PRINT_COMPILE_SWIG)\n" ;
    print MAKEFILE "\t\$(ECHO_CMD)\$(TRICK_CPPC) \$(TRICK_CXXFLAGS) \$(SWIG_CFLAGS) -c \$< -o \$@\n\n" ;

    print MAKEFILE "$swig_src_dir/init_swig_modules.o : $swig_src_dir/init_swig_modules.cpp\n" ;
    print MAKEFILE "\t\$(PRINT_COMPILE_SWIG)\n" ;
    print MAKEFILE "\t\$(ECHO_CMD)\$(TRICK_CPPC) \$(TRICK_CXXFLAGS) \$(SWIG_CFLAGS) -c \$< -o \$@\n\n" ;

    print MAKEFILE "TRICK_FIXED_PYTHON = \\
 $swig_sim_dir/swig_double.py \\
 $swig_sim_dir/swig_int.py \\
 $swig_sim_dir/swig_ref.py \\
 $swig_sim_dir/shortcuts.py \\
 $swig_sim_dir/unit_test.py \\
 $swig_sim_dir/sim_services.py \\
 $swig_sim_dir/exception.py\n\n" ;
    print MAKEFILE "S_main: \$(TRICK_FIXED_PYTHON)\n\n" ;

    print MAKEFILE "\$(TRICK_FIXED_PYTHON) : $swig_sim_dir/\% : \${TRICK_HOME}/share/trick/swig/\%\n" ;
    print MAKEFILE "\t\$(ECHO_CMD)/bin/cp \$< \$@\n\n" ;

    foreach (keys %swig_dirs) {
        print MAKEFILE "$_:\n" ;
        print MAKEFILE "\tmkdir -p $_\n\n" ;
    }

    print MAKEFILE "\n" ;
    close MAKEFILE ;
    close LINK_PY_OBJS ;

    open SWIGLIB , ">build/S_library_swig" or return ;
    foreach my $f ( @temp_array2 ) {
        print SWIGLIB "$f\n" ;
    }
    close SWIGLIB ;

    open TOPFILE , ">build/top.i" or return ;
    print TOPFILE "\%module top\n\n" ;
    print TOPFILE "\%{\n#include \"../S_source.hh\"\n\n" ;
    foreach my $inst ( @{$$sim_ref{instances}} ) {
        print TOPFILE "extern $$sim_ref{instances_type}{$inst} $inst ;\n" ;
    }
    foreach my $integ_loop ( @{$$sim_ref{integ_loop}} ) {
       print TOPFILE "extern IntegLoopSimObject $$integ_loop{name} ;" ;
    }

    print TOPFILE "\n\%}\n\n" ;
    print TOPFILE "\%import \"build$wd/S_source.i\"\n\n" ;
    foreach my $inst ( @{$$sim_ref{instances}} ) {
        print TOPFILE "$$sim_ref{instances_type}{$inst} $inst ;\n" ;
    }
    foreach my $integ_loop ( @{$$sim_ref{integ_loop}} ) {
       print TOPFILE "IntegLoopSimObject $$integ_loop{name} ;" ;
    }
    close TOPFILE ;

    open INITSWIGFILE , ">build/init_swig_modules.cpp" or return ;
    print INITSWIGFILE "extern \"C\" {\n\n" ;
    foreach $f ( @temp_array2 ) {

        my $md5_sum = md5_hex($f) ;
        print INITSWIGFILE "void init_m${md5_sum}(void) ; /* $f */\n" ;
    }
    print INITSWIGFILE "void init_sim_services(void) ;\n" ;
    print INITSWIGFILE "void init_top(void) ;\n" ;
    print INITSWIGFILE "void init_swig_double(void) ;\n" ;
    print INITSWIGFILE "void init_swig_int(void) ;\n" ;
    print INITSWIGFILE "void init_swig_ref(void) ;\n" ;

    print INITSWIGFILE "\nvoid init_swig_modules(void) {\n\n" ;
    foreach $f ( @temp_array2 ) {
        next if ( $f =~ /S_source.hh/ ) ;
        my $md5_sum = md5_hex($f) ;
        print INITSWIGFILE "    init_m${md5_sum}() ;\n" ;
    }

    print INITSWIGFILE "    init_m${s_source_md5}() ;\n" ;

    print INITSWIGFILE "    init_sim_services() ;\n" ;
    print INITSWIGFILE "    init_top() ;\n" ;
    print INITSWIGFILE "    init_swig_double() ;\n" ;
    print INITSWIGFILE "    init_swig_int() ;\n" ;
    print INITSWIGFILE "    init_swig_ref() ;\n" ;
    print INITSWIGFILE "    return ;\n}\n\n}\n" ;
    close INITSWIGFILE ;

    open INITFILE , ">trick/__init__.py" or return ;

    print INITFILE "import sys\n" ;
    print INITFILE "import os\n" ;
    print INITFILE "sys.path.append(os.getcwd() + \"/trick\")\n" ;

    foreach $m ( keys %python_modules ) {
        next if ( $m eq "root") ;
        my ($temp_str) = $m ;
        $temp_str =~ s/\./\//g ;
        print INITFILE "sys.path.append(os.getcwd() + \"/trick/$temp_str\")\n" ;
    }
    print INITFILE "\n" ;
    print INITFILE "import _sim_services\n" ;
    print INITFILE "from sim_services import *\n\n" ;

    print INITFILE "# create \"all_cvars\" to hold all global/static vars\n" ;
    print INITFILE "all_cvars = new_cvar_list()\n" ;
    print INITFILE "combine_cvars(all_cvars, cvar)\n" ;
    print INITFILE "cvar = None\n\n" ;

    foreach $m ( keys %python_modules ) {
        next if ( $m eq "root") ;
        my ($temp_str) = $m ;
        $temp_str =~ s/\//\./g ;
        print INITFILE "import $temp_str\n" ;
    }
    print INITFILE "\n" ;

    foreach $f ( @{$python_modules{"root"}} ) {
        next if ( $f =~ /S_source.hh/ ) ;
        my $md5_sum = md5_hex($f) ;
        print INITFILE "# $f\n" ;
        print INITFILE "import _m${md5_sum}\n" ;
        print INITFILE "from m${md5_sum} import *\n" ;
        print INITFILE "combine_cvars(all_cvars, cvar)\n" ;
        print INITFILE "cvar = None\n\n" ;
    }

    print INITFILE "# S_source.hh\n" ;
    print INITFILE "import _m${s_source_md5}\n" ;
    print INITFILE "from m${s_source_md5} import *\n\n" ;
    print INITFILE "import _top\n" ;
    print INITFILE "import top\n\n" ;
    print INITFILE "import _swig_double\n" ;
    print INITFILE "import swig_double\n\n" ;
    print INITFILE "import _swig_int\n" ;
    print INITFILE "import swig_int\n\n" ;
    print INITFILE "import _swig_ref\n" ;
    print INITFILE "import swig_ref\n\n" ;
    print INITFILE "from shortcuts import *\n\n" ;
    print INITFILE "from exception import *\n\n" ;
    print INITFILE "cvar = all_cvars\n\n" ;
    close INITFILE ;

    foreach $m ( keys %python_modules ) {
        next if ( $m eq "root") ;
        my ($temp_str) = $m ;
        $temp_str =~ s/\./\//g ;
        if ( ! -e "trick/$temp_str" ) {
            mkpath("trick/$temp_str", {mode=>0775}) ;
        }
        open INITFILE , ">trick/$temp_str/__init__.py" or return ;
        foreach $f ( @{$python_modules{$m}} ) {
            next if ( $f =~ /S_source.hh/ ) ;
            my $md5_sum = md5_hex($f) ;
            print INITFILE "# $f\n" ;
            print INITFILE "import _m${md5_sum}\n" ;
            print INITFILE "from m${md5_sum} import *\n\n" ;
        }
        close INITFILE ;

        while ( $temp_str =~ s/\/.*?$// ) {
            open INITFILE , ">trick/$temp_str/__init__.py" or return ;
            close INITFILE ;
        }
    }

    return ;

}

1;

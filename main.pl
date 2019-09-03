#!/usr/bin/perl -w 
#####
# Begun : 20190215
# Latest Revision : 20190215
# Version : 2.2
# Changes: Added new return-to-start protocol for shapes
#
#####

#.1. For commented code

#Program Details
	my $version = 2.2;
	my $date = "2019/02/15";

#Generic settings
	use strict; #Compile-time errors 
	use warnings; #Syntax warnings
	no warnings 'deprecated'; #Turns of deprecated warnings (esp. from use of Goto statement)
	
#Additional Modules included
	use Time::HiRes qw(time usleep); 
	use Time::Piece; 
	use Device::SerialPort;  #.1.
	use FileHandle; 
	use POSIX qw(:termios_h); 
	use Fcntl qw(F_SETFL F_GETFL O_NONBLOCK);
	use Tk; #GUI
	use Switch; #Switch case blocks
	use Sort::Naturally qw(nsort); #for alphanumeric sorting
	use File::Spec;
        use Cwd;
       

#Bookkeeping Variables
	my $verbose = 1; #Triggers additional terminal output

#################################
####Global Variables
#################################

	#Device addresses
		#Serial Port (UltimusV Extruder)
		my $ext_prt = "/dev/ttyS0"; #Serial Address - may change based on port
		my $ext_dev;  #SerialPort object name

		#Serial Port(3D Printer (Aleph Objects Lulzbot taz6)
		my $taz_prt = "/dev/ttyACM0"; #Serial Address (USB)
		my $taz_dev; #SerialPort object name

	#Session Identifiers
		#Active User
		my $activeUser = "unknown";
	#TODO Implement User profiles with Log folders saved
	
	#Active Files
		my $dir = getcwd;
		my $masterLog = $dir."/Logs/MasterPrintLog".localtime->strftime('%Y%m%d').".txt";
		my $userLog = "None";
		my $gFile = ""; #active gcode file	

	#Cmd arrays for active print job
		my $activeShape ="";
		my @tazCmds; #GCODE
		my @printCmds; #Perl code to execute print
		my $CmdsCurrent =0;
	
	#User Input helper variables
		my $input = "";
		my $lastCmd = "";
		my $savedCmd = "";
	
	#UltimusV RS-232 Command hashes
		my %ExCmd2Char = ("STX" => chr(0x02), "ETX" =>chr(0x03), "ACK"=>chr(0x06), "NAK"=>chr(0x15),"ENQ"=>chr(0x05),"EOT"=>chr(0x04));
		my %ExChar2Cmd = reverse %ExCmd2Char;

	#Shape printing data arrays
		#Row 0 is index of parameter value
		#Row 1 is data value strings
		my @plateData = ([1,2,3,4,5,6,7],["No Name entered", "60","1","10","10","0020","0","+","0","+","0"]);
		my @gapLineData = ([1,2,3,4,5,6,7,8,9,10],["No Name entered", "400","10","10",".5",".1",".5","0014","0014","0000"]);
		my @lineData = ([1,2,3,4,5,6,7,8],["No Name entered", "100","20","20","0","1.5","0300","0000"]);
		my @electrode1Data = ([1,2,3,4,5,6,7,8,9,10,11],["No Name entered", "100","300","2","0007","0000","5","7","10","10","1"]);
		my @hydroGridData = ([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19],["No Name entered", "10","4","0","10","4","0","6","1","7","300","2000","2000","300","3700","0000","0000","0000","Y","0.5","0.25"]);
		#TODO Transfer to files for templates
	
	#Menu Hashes
				
		my %T1Menu = ("q" => "Quit", 
					"?" => "List Commands",
					"(2) printFile" => "Print from a GCODE file",
					"(1) hardware" => "Manually control hardware", 
					"(0) settings" => "Program options",
					"(4) test" => "Run Test Code",
					"(3) printShapes" => "Print pre-defined shapes");			
						
		my %T2Settings = ("q" => "Quit", 
					"?" => "List Commands",
					"(1) info" => "Program Info",
					"(2) out" => "Toggles level of output details");
		
		my %HardwareCommon =(); 
		IO_hardwareInputsRefresh();
		
		my %T2Hardware = 
			(%HardwareCommon, "q" => "Quit",
			 "?" => "List Commands",			 
			 "(3) shapes" => "Go to shapes menu",
			 "(4) printFile" => "Go to printFile menu");
		
		my %T2PrintFile = ("q" => "Quit", 
					"?" => "List Commands",
					"(0) setZero" => "Perform Origin set sequence",
					"(1) pickFile" => "Pick a GCODE file",
					"(2) printFile"	=> "Execute print sequence",
					"(3) fileText" => "Display GCODE file");
				
			my %T3TazOrigin = (%HardwareCommon, "q" => "Quit",
				 "?" => "List Commands",
				 "done" => "Tip is at 0,0,0");
		
			my %T3PrintFileOptions = 
				("q" => "Quit",
				 "?" => "List Commands",
				 "L" => "Advanced Log Options",
				 "(9) execute" => "Start print sequence",
				 "(6) genCmds" => "Generate command arrays",
				 "(8) dispCode" => "Display printing code",
				 "(7) dispCmds" => "Display current commands",
				 "(0) clean" => "raise/lower 20mm",
				 "(1) hardware" => "Go to hardware menu",
				 "(2) plot" => "Select Plotter Mode (No Extruder))",
				 "(3) constPres" => "Select Constant Dispense Pressure Mode",
				 "(4) varPres" => "Select Variable Dispense Pressure Mode");
				 
		
							 
		my %T2PrintShapes = ("q" => "Quit",
						 "STOP" => "Emergency STOP",
						 "?" => "List Commands",
						 "L" => "Advanced Log Options",
						 "(0) clean" => "raise/lower 20mm",
						 "(1) hardware" => "Go to hardware menu",
						 "(2) plate" => "Print plate",
						 "(3) gapLine" => "Print Broken Line",
						 "(4) cuboid" => "Print cuboid",
						 "(5) electrode1" => "Print electrode1",
						 "(6) Line" => "Print Simple Line +Reset",
						 "(7) hydroGrid" => "Print Hydrogel Grid Pattern");
		
		
		
#################################################
####Start main loop
#################################################
IO_mainUI(); #Runs IO interface

#################################################
####Main UI Code
#################################################

sub IO_mainUI {
	#setup the hardware interfaces
	ext_init();
	taz_init();
	
	#Start Screen
	IO_startText(); 
	
	#Loop condition
		my $quit = 0;
		
	#Start IO loop. Tree structure: T1 = IO_mainUI menu, T2,T3 = submenus
	until ($quit==1) {
		#taz_writeReady("M117 PolyPrintBP...\n"); #LCD Status Message
		#taz_readLine();	#clear taz input	
			
		IO_printMenu("Main", %T1Menu);
		print("\nEnter Command: ");	
		$input = <STDIN>;
		chomp($input);
		
		switch ($input) {
			case "q" {$quit = 1;}
			case "?" { #Print options
				#goes to print menu line at start of switch
			}#end T1 case				
			case ["settings","0"]{ #T2 Menu for program settings
				SETTINGS:
				$input = ""; #Text input
				my $done = 0; #Switch iterator		
				until ($done==1) {
					IO_printMenu("File Settings",%T2Settings);
					print("\nEnter Command: ");				
					$input = <STDIN>; #pull input
					chomp($input); #eliminate spaces
					switch ($input) {
						case "q" { #quit
							$done = 1;
						}
						case "?" { #Print options
							#goes to print menu line at start of switch
						}
						case ["1","info"] { #Prints program info
							print("PolyPrintBPv".$version." ".$date." By Bijal Patel bbpatel2\@illinois.edu\n");
						}
						case ["2","out"] { #toggles verbose
							$verbose = 1-$verbose;
							if ($verbose) {print("\tMore Details will be displayed.\n");}
							else {print("\tFewer Details will be displayed.\n");}
						}					
						else {
							print("Input not recognized-try again, \"?\" for cmd list\n");
						}#End T2 case
					}#end T2switch
				}#end T2loop	
			}#end T1 case
			case ["1","hardware"]{#T2 Menu for manual hardware control
				HARDWARE:  #Label for hardware menu for quick switch gotos
				taz_writeReady("G91\n"); #Relative Positioning
				$input = ""; #text input
				my $done = 0; #loop variable	
								
				until ($done==1) { #T2 menu loop
					taz_writeReady("M117 Manual Ctrl...\n"); #LCD Status Message
					IO_printMenu("Hardware",%T2Hardware);
					print("WARNING: Sending commands directly to hardware can be risky!\n");
					print("Enter (GCODE) command: ");					
					
					$input = <STDIN>; #pull input text
					chomp($input); #remove spaces				
					
					#Run input through the common hardware functions
					#RESERVED switch cases: STOP; clean,0; lift,1; ext,2; last,/;m,.,s,x,z,a, w
					unless (IO_hardwareInputs($input)){#Subroutine returns 1 if action completed
					
						switch ($input) { #T2 Switch
							case "q" { #quit
								$done = 1;
							}
							case ["?",""] { #display options
								#goes to print menu line at start of switch
							}
							case ["shapes","3"] { #Goto print shapes menu
								goto SHAPES;
							}		
							case ["printFile","4"] { #Goto print shapes menu
								goto PRINTFILEOPTIONS;
							}				
							else {#send input to Taz as gcode
								$lastCmd = $input;
								if (length($input) > 3){
									taz_writeReady($input."\n");
								}
							}#end T2case
						}#end T2 switch
					}
					#Refresh MenuHashes
						IO_hardwareInputsRefresh();
						#Update Hardware Menu 
						%T2Hardware = 
							(%HardwareCommon, "q" => "Quit",
							"?" => "List Commands",			 
							"(3) shapes" => "Go to shapes menu",
							"(4) printFileOptions"=> "Go to print File Options Menu");
				}#end T2loop	
			}#end T1case
			
			
			case ["2","printFile"]{ #T2 Menu for printing from file
				$input = ""; #Text input
				my $done = 0; #Switch iterator		
				until ($done) {
					taz_writeReady("M117 Printing from File...\n"); #LCD Status Message
					IO_printMenu("Printing from GCODE File",%T2PrintFile);
					print("\nEnter Command: ");	
					$input = <STDIN>; #pull input
					chomp($input); #eliminate spaces
					
					switch ($input) {
						case "q" { #quit
							$done = 1;
						}
						case "?" { #Print options
							#goes to print menu line at start of switch
						}
						case ["setZero","0"] { #Allow user to manually set 0 of axes
						
							#Prompt if sure set zero is desired
							print("\t!!!!!Warning - Make sure bed area is clear!!!!!!!!\n\t!!!!!!Homing can be dangerous!!!!!!\n\t???Are you sure??? (Y/N):");
							my $in = <STDIN>; chomp($in);
							#if yes, continue
							if ($in eq "Y") {
							
							taz_writeReady("M117 Setting Origin...\n"); #LCD Status Message						
							taz_writeReady("G1 F1000 Z20\n"); #Lift Z-axis by 20
							taz_writeReady("G28 XY\n"); #Home XY with switches
							taz_writeReady("G91\n"); #R’elative Positioning					
							taz_writeReady("G1 F1000 X10 Y-10\n"); #Move off from ends a bit
																			
								#Ask if home sequence okay before proceeding						
								print("XY Axes Homed okay? Y/N: ");
								$in = <STDIN>; chomp($in);
								#if yes, continue
								if ($in eq "Y") {
									taz_writeReady("G1 F2000 X145 Y-165\n"); #Move to roughly center
									
									#Let user control all axes to move into substrate contact
									my $zeroed = 0;
										print("MANUAL ZERO: MOVE TIP TO (0,0,0)\n");
									until ($zeroed == 1){
										#Refresh Hash then print Menu
											IO_hardwareInputsRefresh();
											%T3TazOrigin = (%HardwareCommon, "q" => "Quit",
												"?" => "List Commands",
												"done" => "Tip is at 0,0,0");
											IO_printMenu("Taz Origin", %T3TazOrigin);		
											print("Enter (GCODE) Command: ");								
										
										my $in = <STDIN>; chomp $in;
										
										#Run input through the common hardware functions
										#RESERVED switch cases: STOP; clean,0; lift,1; ext,2; last,/;m,.,s,x,z,a, w
										unless (IO_hardwareInputs($in)){#Subroutine returns 1 if action completed
											switch ($in) {
												case "q" { #exit loop
													$zeroed=1;
												}
												case "s" { #send emergency stop
													taz_write("M112\n");
												}
												case ["?",""] { #display options
													#goes to print menu line at start of switch
												}
												case "done" { #set origin to zero, lift up, exit
													$zeroed=1;
													taz_writeReady("G92 X0 Y0 Z0\n");
													taz_writeReady("G90\n"); #Relative Positioning
													print("Origin Set!\n");
												}
												else { #Execute GCode motions
													$lastCmd = $in;
													taz_writeReady($in."\n");
												}
											}
										}
									}
								}
							}
						}#end T2 case
						case ["pickFile","1"] { #Selects a file to read
							$gFile = IO_openFile();
							$CmdsCurrent =0;
						}
						case ["printFileOptions","2"] { #Goes to advanced print menu
							PRINTFILEOPTIONS: #Label for printFile goto quick switch
							IO_printFileOptions();
						}
						case ["fileText","3"] { #Displays GCode text
							IO_dispFile();
						}
						
						else {
							print("Input not recognized-try again, \"?\" for cmd list\n");
						}
					}#end T2switch
				}#end T2loop	
			}#end T1 case
			case ["3","printShapes"] { #T2 Menu for printing preset shapes
				SHAPES: #Label for shapes goto quick switch
				taz_writeReady("ShapesMenu...\n"); #LCD Status Message				
				$input = ""; #Text input
				my $done = 0; #Switch iterator		
				until ($done==1) {
					
					IO_printMenu("Print Shapes",%T2PrintShapes);
					
					print ("\n\tSaving current position.....");
					my @startXY = taz_getAbsPosXY();
					print("\tPosition Saved!");
					
					print("\nEnter Command: ");	
					
					my $isShapeCmd = 1;
								
					$input = <STDIN>; #pull input
					chomp($input); #eliminate spaces
					switch ($input) {					
						case "q" { #quit
							$done = 1;
							$isShapeCmd =0;
						}
						case "?" { #Print options
							#goes to print menu line at start of switch
							$isShapeCmd =0;
						}
						case "L" { #Choose Log File
							$userLog=IO_saveFile();
							$isShapeCmd =0;
						}
						case ["clean","0"] { #Lifts up and then lowers back slowly
							IO_clean();
							$isShapeCmd =0;
						}#end T2 case
						case ["1", "hardware"] { #go to hardware menu
							goto HARDWARE;
						}
						case ["plate","2"] { #prints plate
							#Hash of printing parameters and corresponding index in data array
							my %plateParam = (
								"(1) Sample Name (optional)" => 0,
								"(2) Printing Speed (mm/min)"=> 1,
								"(3) Center-to-center Y spacing (mm)" => 2,
								"(4) X-length (mm)" => 3,
								"(5) Y-length (mm)" => 4,
								"(6) Extrusion \"ON\" pressure (kPa)" => 5,
								"(7) Pressure Increment [per pair] (kPa)" => 6,
								"(8) Pressure Operation [per pair] (*or+)" => 7,
								"(9) Speed Increment [per pair] (mm/min)" => 8,
								"(10) Speed Operation [per pair] (*or+)" => 9,
								"(11) Clean toggle? (1-true, 0-false)" => 10);					
							
							#Ask user/ get new parameters see if user wants to proceed
							my $userStatus = IO_getParams("Plate", \%plateParam,\@plateData);
												
							unless ($userStatus == 0){ #unless user wants to quit		
								
								#Execute print sequence	
								#Print log start
								IO_log("Plate", \%plateParam,\@plateData,1);
																										
								#Current config: 1 layer, wxl mm
								taz_writeReady("G1 F60 Y-.5\n"); #Move fwd
								my $vxy = $plateData[1][1]; 
								my $w = $plateData[1][2]; #line thickness + OFFSET
								my $length = $plateData[1][3]; #X length
								my $width = $plateData[1][4]; #Y length
								my $extPres = $plateData[1][5]; #"ON" pressure
								my $presInc = $plateData[1][6]; #Pressure incrementer
								my $presOp = $plateData[1][7]; #Pressure modifier
								my $vInc = $plateData[1][8]; #Speed incrementer
								my $vOp = $plateData[1][9]; #Speed modifier
								my $doClean = $plateData[1][10]; #clean or no
								
								my $cleanPres = "0030"; #Cleaning pressure	
								my $basePres = "0030";#"OFF" pressure
								my $cleantime = "0"; #cleaning time	
												
								#calc how many sets of rows to print
								my $numRow = $width/(2*$w);
										
									ext_dlCMD("PS  ",$extPres);	#set to extrusion pressure		
									ext_dlCMD("DI ",""); #start dispense
					
									foreach my $i(1..$numRow){
										ext_dlCMD("PS  ",$extPres);	#set to extrusion pressure
										#Move LR
										taz_writeReady("G1 F".$vxy." X".$length."\n"); #start motion
										#ext_dlCMD("PS  ",$extPres);	#set to extrusion pressure
										#ext_dlCMD("DI ",""); #start dispense
										#taz_readLine();
						
										taz_writeReady("G1 F".$vxy." Y-".$w."\n");#Move fwd
										#ext_dlCMD("PS  ",$basePres);	#set tobase pressure
										#ext_dlCMD("DI ",""); #stop dispense
										#taz_readLine();
										
=cut										#clean routine
										if ($doClean){
											taz_writeReady("G1 F100 X2\n"); #move clear 		
											ext_dlCMD("PS  ",$cleanPres);	#set tocleaning pressure
											#ext_dlCMD("DI ",""); #start dispense
											sleep($cleantime); #dispense 1 seconds
											ext_dlCMD("PS  ",$basePres);	#set tobase pressure
											#ext_dlCMD("DI ",""); #End dispense
											#taz_readLine();
											
											taz_writeReady("G1 F100 X-2\n"); #move to active
											ext_dlCMD("PS  ",$extPres);	#set to extrusion pressure			
											#taz_readLine();
										}
=cut										
										#Move RL
										taz_writeReady("G1 F".$vxy." X-".$length."\n"); #start motion
										#ext_dlCMD("DI ","");	#start dispense		
										#taz_readLine();				
										
										#FWD
										taz_writeReady("G1 F".$vxy." Y-".$w."\n");#Move fwd
										#ext_dlCMD("PS  ",$basePres);	#set tobase pressure
										#ext_dlCMD("DI ","");	#stop dispense		
										#taz_readLine();
										
=cut									
										#clean routine
										if ($doClean){
											taz_writeReady("G1 F100 X-2\n"); #move clear
											ext_dlCMD("PS  ",$cleanPres);	#set tocleaning pressure
											#ext_dlCMD("DI ",""); #start dispense
											sleep($cleantime); #dispense 1 seconds
											ext_dlCMD("PS  ",$basePres);	#set tobase pressure
											#ext_dlCMD("DI ",""); #End dispense
											#taz_readLine();
											
											taz_writeReady("G1 F100 X2\n"); #move to active
											ext_dlCMD("PS  ",$extPres);	#set to extrusion pressure			
											#taz_readLine();
										}
=cut										
										#increment ext. pressure
										$extPres = u_presMod($extPres,$presOp,$presInc);
										#increment speed
										$vxy = u_vMod($vxy,$vOp,$vInc);			
									}	
									ext_dlCMD("DI ",""); #end dispense
									taz_writeReady("G1 F1000"." Z20\n");#Move up for end			
									
									#Print log end
									IO_log("Plate", \%plateParam,\@plateData,0);
							}
						}#end T2 case
						case ["gapLine","3"] { #prints line with a gap in it
							#see gapLineData array for presets
							#my @gapLineData = ([1,2,3,4,5,6],["400","10",".1",".5","0002","0002"]);
						
							#Hash of printing parameters and corresponding index in data array
							my %gapLineParam = (
								"(1) Sample Name (optional)" => 0,
								"(2) Printing Speed (mm/min)"=> 1,
								"(3) Total X-length (mm)" => 2,
								"(4) Total Y-length (mm)" => 3,
								"(5) Y-spacing (mm)" => 4,
								"(6) X-Gap length (mm)" => 5,
								"(7) Z-hop height (mm)" => 6,
								"(8) Extrusion \"ON\" pressure (kPa)" => 7,
								"(9) Extrusion \"OFF\" pressure (kPa)" => 8,
								"(10) Extrusion \"Travel\" pressure (kPa)" => 9);					
							
							#Ask user/ get new parameters see if user wants to proceed
							my $userStatus = IO_getParams("Gap Line", \%gapLineParam,\@gapLineData);
												
							unless ($userStatus == 0){ #unless user wants to quit
								#Print log start
								IO_log("Gap Line", \%gapLineParam,\@gapLineData,1);
								
								my $vxy = $gapLineData[1][1]; #mm/min
								my $xLength = $gapLineData[1][2]; #Total X-line length
								my $yLength = $gapLineData[1][3]; #Total Y-line length
								my $ySpace = $gapLineData[1][4]; #Total Y gap length
								my $xGapLength = $gapLineData[1][5]; #Total X-Gap length
								my $zGap = $gapLineData[1][6]; #z-gap
								my $extPres = $gapLineData[1][7]; #"ON" pressure
								#print("EXTPRES".$extPres);
								my $offPres = $gapLineData[1][8]; #"OFF" pressure
								#print("OFFPRES".$offPres);
								my $travelPres = $gapLineData[1][9]; #"Travel" pressure
								#print("TravPRES".$travelPres);
																						
								#calculated
								my $xDist = ($xLength - $xGapLength)/2;
								my $numRow = $yLength/(2*$ySpace);
										
									
								ext_dlCMD("DI ",""); #start dispense
								taz_writeReady("G91\n"); #relative positioning
								#taz_readLine();
								
								
								foreach my $i(1..$numRow){
									
									ext_dlCMD("PS  ",$extPres);	#set to extrusion pressure	
									print("\n\n\nSTART OF LOOP PSET SHOULD BE 2\n\n\n");
									
									#Move LR
									taz_writeReady("G1 F".$vxy." X".$xDist."\n"); #start motion
									#taz_readLine();
									
									#Lift/Stop
									ext_dlCMD("PS  ",$offPres);	#set to "OFF" pressure
									print("\n\n\nOFF OF LOOP PSET SHOULD BE 0000\n\n\n" );
									
									
									
									taz_writeReady("G1 F200 Z".$zGap."\n"); #Move up
									#taz_readLine();
									
									taz_writeReady("G1 F200 X".$xGapLength."\n"); #Move LR
									#taz_readLine();
									
									taz_writeReady("G1 F200 Z-".$zGap."\n"); #Move down
									#taz_readLine();
									
									#Move LR
									ext_dlCMD("PS  ",$extPres);	#set to extrusion pressure		
									print("\n\n\n ON LOOP PSET SHOULD BE 0002\n\n\n" );
									
									
									taz_writeReady("G1 F".$vxy." X".$xDist."\n"); #start motion
									#taz_readLine();
									
									#Reset to next line position
									ext_dlCMD("PS  ",$travelPres);	#set to travel pressure	
									print("\n\n\n Travel PSET SHOULD BE 0003\n\n\n" );
									
									
									taz_writeReady("G1 F300 Z4\n"); #lift up
									#taz_readLine();
									
									taz_writeReady("G1 F1000 Y-" .$ySpace. "\n"); #move down
									#taz_readLine();
									
									taz_writeReady("G1 F1500 X-" .$xLength. "\n"); #move left
									#taz_readLine();
									
									taz_writeReady("G1 F300 Z-4\n"); #move down
									#taz_readLine();
								}
								#Move up and reset position
								ext_dlCMD("DI ",""); #stop dispense
								taz_writeReady("G1 F500 Z20"); #Move up and left
								#Print log end
								IO_log("Gap Line", \%gapLineParam,\@gapLineData,0);
							}
						}#End T2case
						
						case ["electrode1","5"] { #prints electrode pattern
							#see gapLineData array for presets
							#my @gapLineData = ([1,2,3,4,5,6],["400","10",".1",".5","0002","0002"]);
						
							#Hash of printing parameters and corresponding index in data array
							my %electrode1Param = (
								"(1) Sample Name (optional)" => 0,
								"(2) Printing Speed (mm/min)"=> 1,
								"(3) Travel Speed (mm/min)" => 2,
								"(4) Contact Dwell time (s)" => 3,
								"(5) Extrusion \"ON\" pressure (kPa)" => 4,
								"(6) Extrusion \"Travel\" pressure (kPa)" => 5,
								"(7) X1 (mm)" => 6,
								"(8) X2 (mm)" => 7,
								"(9) Y1 (mm)" => 8,
								"(10) Y2 (mm)" => 9,
								"(11) Width (mm)" => 10,
								#"(6) Z-hop height (mm)" => 5,
								);					
							
							#Ask user/ get new parameters see if user wants to proceed
							my $userStatus = IO_getParams("electrode1", \%electrode1Param,\@electrode1Data);
												
							unless ($userStatus == 0){ #unless user wants to quit
								#Print log start
								IO_log("electrode1", \%electrode1Param,\@electrode1Data,1);
								
								my $vPrint = $electrode1Data[1][1]; #mm/min
								my $vTravel = $electrode1Data[1][2]; #travel speed mm/min
								my $tDwell = $electrode1Data[1][3]; #dwell time (s)
								my $extPres = $electrode1Data[1][4]; #"ON" pressure
								my $travelPres = $electrode1Data[1][5]; #"Travel" pressure
								my $x1 = $electrode1Data[1][6]; #x1
								my $x2 = $electrode1Data[1][7]; #x2
								my $y1 = $electrode1Data[1][8]; #y1
								my $y2 = $electrode1Data[1][9]; #y2
								my $w = $electrode1Data[1][10]; #width
								
								my $zHeight =3; #mm		
																	
								#calculated
								my $totalDY = $y2+$w;
								my $xTrav = $x2-$x1;
								
								if	($xTrav>0)
								{
									$xTrav = "-".$xTrav;
								}
								
									
								ext_dlCMD("PS  ",$extPres);	#set to extrusion pressure								
								ext_dlCMD("DI ",""); #start dispense
								taz_writeReady("G91\n"); #relative positioning
								#taz_readLine();
																									
								#Dwell one
									sleep($tDwell);
								
								#Move 'south'
									taz_writeReady("G1 F" .$vPrint. " Y-" .$y1. "\n"); #move south
									#taz_readLine();
								
								#Move 'west'
									taz_writeReady("G1 F" .$vPrint. " X-" .$x1. "\n"); #move west
									#taz_readLine();
									
								
								#Stop dispense, move up
								
									taz_writeReady("G1 F" .$vTravel. " Z3 \n"); #move up
									#taz_readLine();
									
									ext_dlCMD("PS  ",$travelPres);	#set to travel pressure							
									
									
									#Travel 'south'
									taz_writeReady("G1 F" .$vTravel. " Y-" .$totalDY. "\n"); #move south
									#taz_readLine();
									
									#Travel 'West'
									taz_writeReady("G1 F" .$vTravel. " X" .$xTrav. "\n"); #move West
									#taz_readLine();
								
								# Make contact 2, lower, dispense, dwell
									taz_writeReady("G1 F" .$vTravel. " Z-3 \n"); #move down
									#taz_readLine();
								
									ext_dlCMD("PS  ",$extPres);	#set to extrusion pressure								
									
									sleep($tDwell);
								
								#Move 'north'
									taz_writeReady("G1 F" .$vPrint. " Y" .$y2. "\n"); #move north
									#taz_readLine();
							
								#Move 'east'
									taz_writeReady("G1 F" .$vPrint. " X" .($x2+2). "\n"); #move east
									#taz_readLine();						
													
								#Stop dispense Move up and reset position
								
								taz_writeReady("G1 F500 Z20 X-".$x2."\n"); #Move up and left
								#taz_readLine();
								ext_dlCMD("DI ",""); #stop dispense
								taz_writeReady("G1 F500 Y".($y1+$w)."\n"); #Move up and left
								#taz_readLine();
								#Print log end
								IO_log("Gap Line", \%electrode1Param,\@electrode1Data,0);
							}
						}#End T2case
						
						case ["line","6"] { #prints simple line
							#see lineData array for presets
							
							#Hash of printing parameters and corresponding index in data array
							my %lineParam = (
								"(1) Sample Name (optional)" => 0,
								"(2) Printing Speed (mm/min)"=> 1,
								"(3) Total X print length (mm)" => 2,
								"(4) End Z-raise" => 3,
								"(5) Additional X Travel (mm)" => 4,
								"(6) End Y-Offset (mm)" => 5,
								"(7) Extrusion \"ON\" pressure (kPa)" => 6,
								"(8) Extrusion \"OFF\" pressure (kPa)" => 7);
												
							
							#Ask user/ get new parameters see if user wants to proceed
							my $userStatus = IO_getParams("Line", \%lineParam,\@lineData);
												
							unless ($userStatus == 0){ #unless user wants to quit
								#Print log start
								IO_log("Line", \%lineParam,\@lineData,1);
								
								my $vxy = $lineData[1][1]; #mm/min
								my $xLength = $lineData[1][2]; #Total X print length (mm)
								my $zRaise = $lineData[1][3]; #End Z-raise
								my $xTravel = $lineData[1][4]; #Additional X Travel (mm)
								my $yOffSet = $lineData[1][5]; #End Y-Offset (mm
								my $extPres = $lineData[1][6]; #"ON" pressure
								my $offPres = $lineData[1][7]; #"OFF" pressure
																						
								#calculated
								my $xDist = $xLength + $xTravel;	
																	
								taz_writeReady("G91\n"); #relative positioning	
								ext_dlCMD("PS  ",$extPres);	#set to extrusion pressure	
								ext_dlCMD("DI ",""); #start dispense										

								#Move LR
								taz_writeReady("G1 F".$vxy." X".$xLength."\n"); #start motion
															
								#Lift/Stop Extrusion
								ext_dlCMD("PS  ",$offPres);	#set to "OFF" pressure							
									
								taz_writeReady("G1 F200 Z".$zRaise."\n"); #Move up
								
								taz_writeReady("G1 F200 X".$xTravel."\n"); #Travel X
																						
								taz_writeReady("G1 F1000 Y-" .$yOffSet. "\n"); #move down
								
								ext_dlCMD("DI ",""); #stop dispense	
								
								#Print log end
								IO_log("Line", \%lineParam,\@lineData,0);
							}
						}#End T2case
						
						case ["cuboid","4"] { #prints cuboid
							#Current config: 4 layer, 7x7
							taz_writeReady("G1 F60 Y-.5\n"); #Move fwd
							my $h = ".10"; #layer height
							my $vxy = "15"; #mm/min
							my $vz = "30";#mm/min
							my $w = ".250"; #line thickness
							my $l = "7"; #line length
				
							foreach my $j(1..2){
								foreach my $i(1..10){
								#Fwd
										taz_writeReady("G1 F".$vxy." X".$l."\n"); #Move LR
										ext_dlCMD("DI ","");
										#taz_readLine();
							
										taz_writeReady("G1 F".$vxy." Y-".$w."\n");#Move fwd
										ext_dlCMD("DI ","");			
										#taz_readLine();
				
										taz_writeReady("G1 F".$vxy." X-".$l."\n"); #Move LR
										ext_dlCMD("DI ","");			
										#taz_readLine();				
										
										taz_writeReady("G1 F".$vxy." Y-".$w."\n");#Move fwd
										ext_dlCMD("DI ","");			
										#taz_readLine();
								}
								#up
									taz_writeReady("G1 F".$vz." Z".$h."\n"); #Move up
									ext_dlCMD("DI ","");
									#taz_readLine();
									taz_writeReady("G1 F".$vxy." Y".$w."\n"); #Move back
										ext_dlCMD("DI ","");
										#taz_readLine();
								foreach my $k(1..10){
									#back
										taz_writeReady("G1 F".$vxy." X".$l."\n"); #Move LR
										ext_dlCMD("DI ","");
										#taz_readLine();
				
										taz_writeReady("G1 F".$vxy." Y".$w."\n"); #Move back
										ext_dlCMD("DI ","");			
										#taz_readLine();
				
										taz_writeReady("G1 F".$vxy." X-".$l."\n"); #Move LR
										ext_dlCMD("DI ","");			
										#taz_readLine();				
										
										taz_writeReady("G1 F".$vxy." Y".$w."\n"); #Move back
										ext_dlCMD("DI ","");
										#taz_readLine();					
								}		
								#up
									taz_writeReady("G1 F".$vz." Z".$h."\n"); #Move up
									ext_dlCMD("DI ","");
									#taz_readLine();
								taz_writeReady("G1 F".$vxy." Y-".$w."\n"); #Move fwd
								ext_dlCMD("DI ","");
								#taz_readLine();-initialdir => "/home/bbpatel/Desktop"
							}
						}#end T2 case
						case ["hydroGrid","7"]{ #printHydrogrid
							#Hash of printing parameters and corresponding index in data array
							my %hydroGridParam = (
								"(1) Sample Name (optional)" => 0,
								"(2) Number of X-lines" => 1,
								"(3) Center-to-center X-line spacing (mm)" => 2,
								"(4) X-tailoff distance" => 3,
								"(5) Number of Y-lines" => 4,
								"(6) Center-to-center Y-line spacing (mm)" => 5,
								"(7) Y-tailoff distance" => 6,
								"(8) Z-Travel height" =>7,
								"(9) Z-layer Height" => 8,
								"(10) Z-Clean Height" => 9,
								"(11) Printing Speed (mm/min)"=> 10,
								"(12) Travel Speed (mm/min)"=> 11,
								"(13) Clean Speed (mm/min)"=> 12,
								"(14) ZExtrusion/Raise Speed (mm/min)"=> 13,
								"(15) Extrusion \"ON\" pressure (kPa)" => 14,
								"(16) Extrusion \"OFF\" pressure (kPa)" => 15,
								"(17) Extrusion \"ZRaise\" pressure (kPa)" => 16,
								"(18) Cleaning pressure (kPa)" => 17,
								"(19) Prompt for clean?" => 18,
								"(20 Dwell time for gluing initial blob" => 19,
								"(21) Height for line termination" => 20);	
											
							
							#Ask user/ get new parameters see if user wants to proceed
							my $userStatus = IO_getParams("HydroGrid", \%hydroGridParam,\@hydroGridData);
												
							unless ($userStatus == 0){ #unless user wants to quit		
								#Execute print sequence	
								#Print log start
								IO_log("HydroGrid", \%hydroGridParam,\@hydroGridData,1);
																										
								#Current config: 
								my $numX = $hydroGridData[1][1]; #Number of X-lines	
								my $xDist = $hydroGridData[1][2]; #Center-to-center Xline spacing (mm)
								my $xTail = $hydroGridData[1][3]; #X-tailoff distance"
								my $numY = $hydroGridData[1][4];	#Number of Y-lines"
								my $yDist = $hydroGridData[1][5]; #Center-to-center Yline spacing (mm)
								my $yTail = $hydroGridData[1][6];	#Y-tailoff distance"	
								my $zTravHeight = $hydroGridData[1][7]; #Z travel height
								my $zLayerHeight = $hydroGridData[1][8];	 #Z-layer Height"	
								my $zCleanHeight = $hydroGridData[1][9]; # Z-Clean Height"
							
								my $vxy = $hydroGridData[1][10]; # Printing Speed (mm/min)
								my $vTrav = $hydroGridData[1][11]; # Travel Speed (mm/min)
								my $vzclean = $hydroGridData[1][12]; # Clean Speed (mm/min)"
								my $vzExt = $hydroGridData[1][13]; # ZExtrusion/Raise Speed
								my $p_ON = $hydroGridData[1][14]; # Extrusion \"ON\" pressure (kPa)"
								my $p_OFF = $hydroGridData[1][15]; #Extrusion \"OFF\" pressure (kPa)
								my $p_zRaise = $hydroGridData[1][16]; ;#"zRaise" pressure
								my $p_clean = $hydroGridData[1][17];#"cleaning" pressure
								my $promptClean = $hydroGridData[1][18]; #Prompt for clean?
								my $tDwell = $hydroGridData[1][19]; #Dwell time for line start
								my $zPressHeight = $hydroGridData[1][20]; #Height for line termination
			
								#TODO Save current position
								
								#math helpers
								my $yLength = ($numX+1)*$xDist;
								my $xLength = ($numY+1)*$yDist;
								my $yOffset = ($yDist-$yTail);
								my $xOffset = ($xDist-$xTail);
								
								#initialize extruder
								ext_dlCMD("PS  ",$p_OFF);	#set to Off pressure
								ext_dlCMD("DI ",""); #start dispense
								
								#Starting off at Y-line 1 origin point at Z-layer height
								my $quitY = 0;
														
								#Print Y-direction blocks
								for (my $y=0; $y < $numY; $y++) {
									
									###Print Anchor Point Start	
										#set to On pressure
											ext_dlCMD("PS  ",$p_ON); 
											
										# Press Down 
											
											#Syringe moves negative z to pressHeight with user input speed
											taz_writeReady("G1 F".$vzExt." Z-".($zLayerHeight-$zPressHeight)."\n");
										# Extrude blob
											
											sleep($tDwell);
										# Lift up
											#Syringe moves positive z to pressHeight with user input speed
											taz_writeReady("G1 F".$vzExt." Z".($zLayerHeight-$zPressHeight)."\n");
										
										#Set off pressure
											#Stop pressure(p_off)
										ext_dlCMD("PS  ",$p_OFF);	
									###Print Anchor Point End
									
									###Print Anchor Point Start	

										# Press Down 
											#Syringe moves negative z to pressHeight with user input speed
											taz_writeReady("G1 F".$vzExt." Z-".($zLayerHeight-$zPressHeight)."\n");

										# Lift up
											#Syringe moves positive z to pressHeight with user input speed
											taz_writeReady("G1 F".$vzExt." Z".($zLayerHeight-$zPressHeight)."\n");
										
									###Print Anchor Point End
									
									
									#set to On pressure
									ext_dlCMD("PS  ",$p_ON); 
									
									#Stage moves space_x*( line_x +1) in negative y direction at user input speed
									taz_writeReady("G1 F".$vxy." Y-".$yLength."\n"); 
									
									
									###Print Anchor Point Start nopause
										# Press Down 
											#Syringe moves negative z to pressHeight with user input speed
											taz_writeReady("G1 F".$vzExt." Z-".($zLayerHeight-$zPressHeight)."\n");
										# Extrude blob

											sleep($tDwell);
										# Lift up
											#Syringe moves positive z to pressHeight with user input speed
											taz_writeReady("G1 F".$vzExt." Z".($zLayerHeight-$zPressHeight)."\n");
										
									###Print Anchor Point End
									
									#Syringe moves tailoff mm in positive x direction with user input speed( y_tailoff)
									taz_writeReady("G1 F".$vxy." X".$yTail."\n");
									
									#Stop pressure(p_off)
									ext_dlCMD("PS  ",$p_OFF);
									
									###Print Anchor Point Start	
										# Press Down 
											#Syringe moves negative z to pressHeight with user input speed
											taz_writeReady("G1 F".$vzExt." Z-".($zLayerHeight-$zPressHeight)."\n");
										# Extrude blob
											#set to On pressure
											ext_dlCMD("PS  ",$p_ON); 
											sleep($tDwell);
										# Lift up
											#Syringe moves positive z to pressHeight with user input speed
											taz_writeReady("G1 F".$vzExt." Z".($zLayerHeight-$zPressHeight)."\n");
										
										#Set off pressure
											#Stop pressure(p_off)
										ext_dlCMD("PS  ",$p_OFF);	
									###Print Anchor Point End
									
									
									#Syringe moves 5mm(z_clean)  in positive z direction with F 100(v_clean) (cut Hydrogel on syringe)
									taz_writeReady("G1 F".$vzclean." Z".$zCleanHeight."\n");
									
									#( pressure_clean)
									ext_dlCMD("PS  ",$p_clean); 
									
									#Prompt continue
									my $inp = IO_getStdInput("\t\tCut Hydrogel, Q to quit, anything else to continue: ");	
									chomp $inp;
									if ($inp eq "Q" || $inp eq "q"){
										$quitY=1;
										last; 
									}#endif
									
									
									#Stop pressure(p_off)
									ext_dlCMD("PS  ",$p_OFF);
									
									
									#Syringe moves z height for travel 
									taz_writeReady("G1 F".$vTrav." Z".$zTravHeight."\n");
									
									#Prompt continue
									$inp = IO_getStdInput("\t\tCut Hydrogel, Q to quit, anything else to continue: ");	
									chomp $inp;
									if ($inp eq "Q" || $inp eq "q"){
										$quitY=1;
										last; 
									}#endif
									
									
									#Syringe moves space_y - 5mm distance in positive x with user input speed 
									taz_writeReady("G1 F".$vTrav." X".$yOffset."\n");
									
									#Stage moves space_x*( line_x +1) in positive y direction at user input speed
									taz_writeReady("G1 F".$vTrav." Y".$yLength."\n"); 
									
									if($y<($numY-1)){
										#Syringe moves 5mm in negative z direction with user input speed
										taz_writeReady("G1 F".$vTrav." Z-".$zCleanHeight."\n");
										#Syringe moves z height for travel 
										taz_writeReady("G1 F".$vTrav." Z-".$zTravHeight."\n");
									}
									
									
								}
								
									if ($quitY != 1){
									#Move to X-origin position
														
										#Syringe moves (line_y+2)* space_y in negative x  with user input speed
										taz_writeReady("G1 F".$vTrav." X-".(($numY+1)*$yDist)."\n");
										
										#Syringe moves  space_x in negative y with user input speed
										taz_writeReady("G1 F".$vTrav." Y-".$xDist."\n");
									
									#Print X-direction blocks
									for (my $x=0; $x < $numX; $x++) {
																								
										#Syringe moves 5mm in negative z with user input speed
										taz_writeReady("G1 F".$vTrav." Z-".($zCleanHeight)."\n");
										
										#Syringe moves z height for travel 
										taz_writeReady("G1 F".$vTrav." Z-".$zTravHeight."\n");
										
										###Print Anchor Point Start	
											#set to On pressure
												ext_dlCMD("PS  ",$p_ON); 
											# Press Down 
												#Syringe moves negative z to pressHeight with user input speed
												taz_writeReady("G1 F".$vzExt." Z-".($zLayerHeight-$zPressHeight)."\n");
											# Extrude blob
												
												sleep($tDwell);
											# Lift up
												#Syringe moves positive z to pressHeight with user input speed
												taz_writeReady("G1 F".$vzExt." Z".($zLayerHeight-$zPressHeight)."\n");
											
											#Set off pressure
												#Stop pressure(p_off)
											ext_dlCMD("PS  ",$p_OFF);	
										###Print Anchor Point End
																				###Print Anchor Point Start	

											# Press Down 
												#Syringe moves negative z to pressHeight with user input speed
												taz_writeReady("G1 F".$vzExt." Z-".($zLayerHeight-$zPressHeight)."\n");

											# Lift up
												#Syringe moves positive z to pressHeight with user input speed
												taz_writeReady("G1 F".$vzExt." Z".($zLayerHeight-$zPressHeight)."\n");
											
										###Print Anchor Point End
										###Print Anchor Point Start	

											# Press Down 
												#Syringe moves negative z to pressHeight with user input speed
												taz_writeReady("G1 F".$vzExt." Z-".($zLayerHeight-$zPressHeight)."\n");

											# Lift up
												#Syringe moves positive z to pressHeight with user input speed
												taz_writeReady("G1 F".$vzExt." Z".($zLayerHeight-$zPressHeight)."\n");
											
										###Print Anchor Point End
										
										
																		
										#Set ON pressure
										ext_dlCMD("PS  ",$p_ON); 
										
										#Syringe moves 1mm in positive z with v_zExt with pressure_z
										taz_writeReady("G1 F".$vzExt." Z".($zLayerHeight*2)."\n");
										
										
										#Syringe moves (line_y+2)*space_y distance in positive x direction with user input speed
										taz_writeReady("G1 F".$vxy." X".(($numY+2)*$yDist)."\n"); 
										
										#set to zRaise pressure
										ext_dlCMD("PS  ",$p_zRaise); 
										
										
										#Syringe moves 2mm in negative z direction with user input speed
										taz_writeReady("G1 F".$vzExt." Z-". (2*$zLayerHeight)."\n");
										
																												
										#set to on pressure
										ext_dlCMD("PS  ",$p_ON); 
										
										
										###Print Anchor Point Start nopause
											# Press Down 
												#Syringe moves negative z to pressHeight with user input speed
												taz_writeReady("G1 F".$vzExt." Z-".($zLayerHeight-$zPressHeight)."\n");
											# Extrude blob

												sleep($tDwell);
											# Lift up
												#Syringe moves positive z to pressHeight with user input speed
												taz_writeReady("G1 F".$vzExt." Z".($zLayerHeight-$zPressHeight)."\n");
											
										###Print Anchor Point End						
										
										
										#Syringe moves tailoff in negative y direction with user input speed
										taz_writeReady("G1 F".$vxy." Y-".$yTail."\n");
									
										#Stop pressure(p_off)
										ext_dlCMD("PS  ",$p_OFF);	
										
										###Print Anchor Point Start	
											# Press Down 
												#Syringe moves negative z to pressHeight with user input speed
												taz_writeReady("G1 F".$vzExt." Z-".($zLayerHeight-$zPressHeight)."\n");
											# Extrude blob
												#set to On pressure
												ext_dlCMD("PS  ",$p_ON); 
												sleep($tDwell);
											# Lift up
												#Syringe moves positive z to pressHeight with user input speed
												taz_writeReady("G1 F".$vzExt." Z".($zLayerHeight-$zPressHeight)."\n");
											
											#Set off pressure
												#Stop pressure(p_off)
											ext_dlCMD("PS  ",$p_OFF);	
										###Print Anchor Point End
															
										#Syringe moves 5mm(z_clean)  in positive z direction with F 100(v_clean) (cut Hydrogel on syringe)
										taz_writeReady("G1 F".$vzclean." Z".$zCleanHeight."\n");
							
										
										#( pressure_clean)
										ext_dlCMD("PS  ",$p_clean); 
										
										#Prompt continue
										my $inp = IO_getStdInput("\t\tCut Hydrogel, Q to quit, anything else to continue: ");	
										chomp $inp;
										if ($inp eq "Q" || $inp eq "q"){
											last; 
										}#endif
										
										#Syringe moves z height for travel 
										taz_writeReady("G1 F".$vTrav." Z".$zTravHeight."\n");
										
																			#Prompt continue
										$inp = IO_getStdInput("\t\tCut Hydrogel, Q to quit, anything else to continue: ");	
										chomp $inp;
										if ($inp eq "Q" || $inp eq "q"){
											$quitY=1;
											last; 
										}#endif
										
										#Syringe moves space_x - 5mm distance in negative y with user input speed 
										taz_writeReady("G1 F".$vTrav." Y-".$xOffset."\n");
										
										
										#Syringe moves (line_y+1)*space_ycdistance in negative x direction with user input speed
										taz_writeReady("G1 F".$vTrav." X-".(($numY+2)*$yDist)."\n");
									}
								}
								#End Sequence
								ext_dlCMD("DI ",""); #end dispense	
								taz_writeReady("G1 F1000"." Z20\n");#Move up for end
									
								#Print log end
								IO_log("hydroGrid", \%hydroGridParam,\@hydroGridData,0);
							}						
						}#end T2case					
						else {
							print("Input not recognized-try again, \"?\" for cmd list\n");
							$isShapeCmd =0;
						}#End T2 case				
					}#end T2switch
					#Return to start if this was a motion cmd
					if ($isShapeCmd){
						#Ask to goto start position XY if this was a motion cmd					
						my $resetXY = 0;
						my $inp = IO_getStdInput("\n\tReturn to starting point? Y/N: ");
						chomp $inp;
						if ($inp eq "Y" || $inp eq "y"){
							taz_goToXY(@startXY);
						}#endif
						}#endif	
				}#end T2loop	
			}#End T1 case
			case ["4","test"] { #executes test code	
				taz_writeReady("TestMenu...\n"); #LCD Status Message
				my $testP = 2.464;
				print("Test Pressure: ".$testP);
				my $y = sprintf("04.1d",$testP);
			}#end T1 case
			else { #Main menu bad input
				print("Input not recognized-try again, \"?\" for cmd list\n");
			}#End T1case
		}#End T1switch
	}#End T1loop

	
	#Close Devices
		taz_stop();
		ext_stop();
		exit(0); #Exits main method
}#End main method

#################################
###Terminal IO Subroutines
#################################

#Displays start screen
sub IO_startText {
	print(("*" x 80) . "\n". ("*" x 80). "\n\n");
	print("\tPolyPrintBP - Version:".$version."\tRevised: " .$date ."\n\n");
	print(("*" x 80)  ."\n" .("*" x 80)  ."\n");	
}

#Prompts user in gui to select a text file
#If GUI canceled, returns 1
#Else returns file address
sub IO_openFile {
	print("\tPrompting for file....\n");
	my $file = Tk::MainWindow->new->getOpenFile(-initialdir => "/home/bbpatel/Desktop") ||print("\tNo File Selected\n");
	if ($file ne 1){
		print ("\tSelected file: $file\n\n");
	}
	return $file;
}

#Prompts user in gui to select a text file to save to/over
#If GUI canceled, returns 1
#Else returns file address
sub IO_saveFile {
	print("\tPrompting for file....\n");
	my $file = Tk::MainWindow->new->getSaveFile(-defaultextension => '.txt', -initialdir => "/home/bbpatel/Desktop") ||print("\tNo File Selected\n");
	if ($file ne 1){
		print ("\tSelected file: $file\n\n");
	}
	return $file;
}

#Prints the IO commands to the terminal by iterating through command hash (sorted alphabetically)
	#Param hash of IO commands and descriptions
	#http://www.perlmonks.org/?node_id=60798
sub IO_printMenu {
	my ($title, %Cmds) = @_;
	print($title ." Menu:\n");
	keys %Cmds; #reset internal iterator
	foreach my $k (nsort keys %Cmds) {
		printf("\t%-25s|  %-25s\n",$k,$Cmds{$k});
	} 
}

#Handles all IO for setting/displaying parameters for shape printing
#Directly modifies data array for given shape
#Returns value for whether to execute shape print or quit
	#Param shape name of type of shape to be printed (for display)
	#Param paramsRef reference to hash of parameter names and corresponding index in data array
	#Param dataRef reference to data array that corresponds to parameter set/shape
	#Return status 0 for quit, 1 to execute print 
sub IO_getParams{
	my ($shape,$paramsRef,$dataRef) = @_; #From specific shape code
	my $input = ""; #Text input
	my $done = 0; #Switch iterator		
	
	#Hash of menu options
	my %ParamIOMenu = ("q" => "Quit",
				 "?" => "List Commands/Help",
				 "(#)" => "Modify Corresponding Parameter",
				 "(0) Go" => "Executes Print sequence");
				 
	until ($done==1) {
		IO_printMenu("Printing ".$shape, %ParamIOMenu); #display menu options	
		print("\t\tCurrent Parameter Values: \n");
		IO_printParams($paramsRef,$dataRef);#pass references to param info and data to printParams
		
		print("\nEnter Command: ");				
		
		$input = <STDIN>; #pull input
		chomp($input); #eliminate spaces
		
		switch ($input) {
			case "q" { #quit
				$done = 1;
				return 0;
			}
			case "?" { #Print options
				print("\tTips\n".
				"\t\tPressures must be entered as 4-digits (kPa) EX: 4.3 kPa -> 0043\n".
				"\t\tDistances must be entered in mm EX: 10.5 mm = 10.5\n");
				
				#goes to print menu line at start of switch
			}
			case ["1","2","3","4","5","6","7","8","9","10","11","12","13","14","15","16","17","18","19","20","21","22","23","24","25"] { #modifies corresponding parameter
				#check if param is within range of modifiable params
				if ($input <= scalar @{$dataRef}[0]){
					print("Modifying parameter: ".$input."\n");
					print("Enter new value: ");	
					my $inParam = <STDIN>; #pull input
					chomp($inParam); #eliminate spaces
					${$dataRef}[1][$input-1] = $inParam;
					print("Updated Parameters:\n");
					IO_printParams($paramsRef,$dataRef);
				}
				else{
					print("Invalid parameter value\n");
				}			
				
			}
			case ["0","go"] { #executes program - leaves switch
				print("Starting Print...\n");
				$done = 1;
				return 1;
			}		
			else {
				print("Input not recognized-try again, \"?\" for cmd list\n");
			}
		}
	}
}

#Prints process parameters to terminal by iterating through paramInfo hash and data array
	#param paramRef reference to hash of process/shape settings and corresponding index in data array
	#param dataRef reference to array of data values
sub IO_printParams{
	my ($paramsRef, $paramsDataRef) = @_; #params from getParams
	keys %{$paramsRef}; #reset internal iterator
		
	foreach my $k (nsort keys %{$paramsRef}) {
		printf("\t\t%-40s|  %-20s\n",$k,${$paramsDataRef}[1][${$paramsRef}{$k}]);
	} 
}



#Writes log of current shape printing to file
	#Param shape name of type of shape to be printed (for display)
	#param paramRef reference to hash of process/shape settings and corresponding index in data array
	#param dataRef reference to array of data values
	#Param isStart boolean for whether start or end of shape
sub IO_log{
	
	my ($shape,$paramsRef, $paramsDataRef,$isStart) = @_; #params
	
	#open log file
	open(masterLOG,'>>',$masterLog); #append to masterLog
	
	unless ($userLog eq "None")
	{
		open(userLOG,'>>',$userLog); #append to masterLog
	}
	
	#for date and time
	my $dateString ="";	
	
	#Different output for start/end of sequence
	if ($isStart){ 
		#Write parameters and description to file
		keys %{$paramsRef}; #reset internal iterator
		$dateString =localtime(); #get current date and time
		my $outString = "Printing: ".$shape."\n\tProcess started at: ".$dateString."\n";
		foreach my $k (nsort keys %{$paramsRef}) {
			$outString .=sprintf("\t\t%-40s|  %-20s\n",$k,${$paramsDataRef}[1][${$paramsRef}{$k}]);
		}
		print masterLOG $outString;
		unless ($userLog eq "None")
		{
			print userLOG $outString;
		}
	}
	else{#Note succesful termination
		
		$dateString =localtime(); #get current date and time
		my $outString = "\tProcess terminated at: ".$dateString."\n";
		
		print masterLOG $outString;
		unless ($userLog eq "None")
		{
			print userLOG $outString;
		}
	} 
	close(masterLOG); #close file
	unless ($userLog eq "None")
	{
		close(userLOG); #close file
	}
}	


#Displays advanced print options before running the print sequence, sending commands back and forth to the printer and extruder
sub IO_printFileOptions {
	taz_writeReady("M117 PrintFileOptions Menu...\n"); #LCD Status Message
	$input = ""; #Text input
	my $done = 0; #Switch iterator
	my $type = "0"; #Type of print sequence		
	
	####Printing Params
		my $pSpeed;
		my $trvSpeed;
		my $zSpeed;
		my $zHeight; #total Z-height to raise
	
	
	until ($done) {
		IO_printMenu("PrintFile Options",%T3PrintFileOptions);
		print("\nChoose Printing Mode: ");				
		$input = <STDIN>; #pull input
		chomp($input); #eliminate spaces
				
		switch ($input) {
			case "q" { #quit
				$done = 1;
			}
			case "?" { #Print options
				#goes to print menu line at start of switch
			}
			case ["L","l"] { #Choose user log file
				$userLog = IO_saveFile();
			}
			case ["clean","0"] { #Lifts up and then lowers back slowly
				IO_clean();
			}
			case ["1", "hardware"] { #go to hardware menu
				goto HARDWARE;
			}
			case ["2","plot"] { #TODOPrint in Plotter Mode (No Extruder)
				$type="plot";
				$CmdsCurrent =0;
				print("\n\tPlotter Mode Parameters:\n'");
				$pSpeed = IO_getStdInput("\tEnter Printing Speed (mm/min): ");
				$trvSpeed = IO_getStdInput("\tEnter Travel Speed (mm/min): ");
				$zSpeed = IO_getStdInput("\tEnter z Speed (mm/min): ");
				$zHeight = IO_getStdInput("\tEnter z-Hop Height (mm): ");
				print("\tPlotter Mode Engaged!\n'");
			}
			
			case ["3","constPres"] { #TODO"Print with Constant Dispense Pressure",
				$type="constPres";
				$CmdsCurrent =0;
				print("\n\tConstant Pressure Mode Parameters:\n'");
				$pSpeed = IO_getStdInput("\tEnter Printing Speed (mm/min): ");
				$trvSpeed = IO_getStdInput("\tEnter Travel Speed (mm/min): ");
				$zSpeed = IO_getStdInput("\tEnter z Speed (mm/min): ");
				$zHeight = IO_getStdInput("\tEnter z-Hop Height (mm): ");
				print("Constant Pressure Mode Engaged!\n");
			
			}
			case ["4","varPres"] { #TODO"Print with variable Dispense Pressure");
				$type="varPres";
				$CmdsCurrent =0;
				print("Under Construction!\n");
			}
			case ["6","genCmds"] { #TODO"genCmds");
				
				$CmdsCurrent =1;
				
				#Empty command arrays
					@tazCmds=(); #GCODE
					@printCmds=(); #Perl code to execute print
				
				#Subroutine for parsing file input into command arrays
					#Param - [Printing Speed, Travel Speed, Z-Speed, Z[height. ]varSpeed = boolean for variable speed rules]
					#Input - None
					#Output - Modifies global @tazCmds array
					#Return - None		
				sub IO_loadTaz{		 
					#Pull params
					my ($printSpeed, $travelSpeed, $zSpeed, $zHeight, $varSpeed) = @_;
										
					#Parse file line by line
					print("\tStep 1: Parsing File...\n");			
					my $readRef = IO_readGFile();
					my @readLines = @$readRef;	
					print("\tFile Parsed!\n");
				
					#Hold Printer Commands
						my @readTaz;
					
					print("\tStep 2: Parsing GCode...\n");
					foreach (@readLines){
							#Split into command blocks and axes blocks			
							my @blocks = split (/\s/, $_);
							
							my $cmdStr = ""; #G,M, etc Cmd
							my $motionStr = ""; #XYZIJK Cmd
							my $feedStr = ""; #F - feedrate cmd
													
							foreach (@blocks) {
								my $c1 = substr($_,0,1);
								switch ($c1) {
									case ["X","Y","I","J","K"] {
										$motionStr .= ($_ ." ");	
									}
									case ["Z"]
									{
										if ($_ eq "Z2.000000"){ #Print
											$motionStr .= "Z".$zHeight." ";
										}
										else
										{
											$motionStr .= ($_ ." ");	
										}
									}
									case ["F"]{
										if ($_ eq "F9999.000000"){ #Print
											$feedStr = "F".$printSpeed;
										}
										elsif ($_ eq "F9998.0"){ #Penetrate
											$feedStr = "F".$zSpeed;
										}
										else{ #Todo variable speed mode by height
											$feedStr = ($_ ." ");
										}
										
									}
										
									case ["G"] {#Special behavior based on type of G cmd
										switch(substr($_,0,3)){ #First 3 characters
											case["G00"]{#Fast Travel Cmd
												$cmdStr .= ($_ ." ");
												$feedStr = "F".$travelSpeed;
											}
											else{
												$cmdStr .= ($_ ." ");
											}						
										}
									}
									else { 
										#Throw away			
									}
								}
							}#End block parsing
						
							#Remove leading or trailing spaces
							$cmdStr = u_trim($cmdStr);
							$motionStr = u_trim($motionStr);
							$feedStr = u_trim($feedStr);							

							#Reassemble full GCODE line
							my $gLine = $cmdStr . " " . $motionStr . " " . $feedStr;
												
							#Add to relevant array
							push(@readTaz,$gLine);
							@tazCmds=@readTaz;
							
						}#End Line parse
					print("\tGCode Parsed!\n");
				}
				
				
				switch($type) { 
					case "0"{
						print("Error - no print mode set");
						$CmdsCurrent =0;
					}
					case "plot"{
						
						#Load GCode Cmds
						IO_loadTaz($pSpeed,$trvSpeed,$zSpeed,$zHeight,0);
						
						print("\tStep 3: Generating Perl Code...\n");
						#Convert to perl code
						foreach my $tCmd (@tazCmds){
							push(@printCmds,"taz_writeReady(\"" . $tCmd . "\\n\");" );
						}
						print("\tPerl Code Generated!\n");
						
					}#End case(plot)
					case "constPres"{
						
						#Load GCode Cmds
						IO_loadTaz($pSpeed,$trvSpeed,$zSpeed,$zHeight,0);
						
						#Identify index for Extruder commands and place in new array]
						my @extIndex=(); #Index BEFORE WHICH extruder dispense command should be inserted
						my @tazCopy = @tazCmds;
						my $dispOn = 0; #dispense status
						chomp(@tazCopy); #Removes all trailing spaces
						
						for my $i (0 .. ($#tazCopy - 1)) {
							if (($tazCopy[$i] eq "G00 Z".$zHeight." F".$trvSpeed) and ($tazCopy[$i+1] eq "G00 Z".$zHeight." F".$trvSpeed)){
								push (@extIndex,$i);
								$dispOn=0;
							 }
							 if ($tazCopy[$i] eq "G01 Z0.000000 F" .$zSpeed) {
								push (@extIndex,$i+1);
								$dispOn=1;
							 }
						}
						
						print("\tStep 3: Generating Perl Code...\n");
						#Convert Taz cmds to perl and insert into printarray
						foreach my $tCmd (@tazCmds){		
							push(@printCmds,"taz_writeReady(\"" . $tCmd . "\\n\");" );
						}

						#Convert extruder commands to perl and insert into print array
						for (my $i=$#extIndex; $i >= 0; $i--){
							splice @printCmds, $extIndex[$i], 0, "ext_dispense();";
						 }						
						#Make sure last dispense is oFF
						if ($dispOn){
							splice @printCmds, $#printCmds-1, 0, "ext_dispense();";
						}
						print("\tPerl Code Generated!\n");		
					}#End case ConstPres
					# case "varPres"{
						# foreach (@readLines)	{
							# #Split into command blocks and axes blocks			
							# my @blocks = split / /, $_;
							# my $cmdStr = "";
							# my $motionStr = "";
							# my $extrudStr = "";			
							# foreach (@blocks) {
								# my $c1 = substr($_,0,1);
								# switch ($c1) {
									# case "X" {
										# $motionStr .= ($_ ." ");	
									# }
									# case "Y" {
										# $motionStr .= ($_ ." ");	
									# }
									# case "Z" {
										# $motionStr .= ($_ ." ");	
									# }
									# case "E" {
										# $extrudStr .= ($_ ." ");	
									# }
									# #G0,G1,F
									# else { 
										# $cmdStr .= ($_ ." ");				
									# }
								# }
							# }
							# #Remove leading or trailing spaces
							# $cmdStr = u_trim($cmdStr);
							# $motionStr = u_trim($motionStr);
							# $extrudStr = u_trim($extrudStr);

							# #See if any extrud commands issued, if not, set to "pause"
							# if ($extrudStr eq "") {
								# $extrudStr = "pause";
							# }								

							# #Reassemble command strings
							# $motionStr = $cmdStr . " " . $motionStr;
							# $extrudStr = $cmdStr . " " . $extrudStr;
					
							# #Add to relevant arrays
							# push(@readTaz,$motionStr);
							# push(@readExt,$extrudStr);			
						# }
					# }#End case varpres
				}#End Switch
						
				
			}#End case 8T4 genCmds
			
			case ["7","dispCmds"]{#Todo Display commands better

				print("Taz Cmds:\n");
				u_printArray(@tazCmds);
			}
			case ["8","dispCode"]{#Todo Display commands better

				print("*****Final Code*******:\n");
				u_printArray(@printCmds);
			}
			case ["9","execute"] { #Executes Print Sequence");
				if($type eq "0"){
					print("\tError: No Print Type selected\n");
				}
				elsif($CmdsCurrent==0){
					print("\tCommands not  up to date with print mode - run genCmds\n");
				}
				else{
					IO_executeFilePrint($type);
				}
			}#End Case9T4
		}#End SwitchT3
	}#End LoopT2
	
	
}#End SubT1

#Runs the print sequence, sending commands back and forth to the printer and extruder
#Input type specifies which printing mode to use (plotting/const pressure/etc)
sub IO_executeFilePrint {
	my $type = shift;
	taz_writeReady("M117 Printing from File...\n"); #LCD Status Message	
#	u_printArray(@printCmds);
	
	my $numCmds = @printCmds;  #number of commands to execute
	#abs positioning
	taz_writeReady("G90\n");
	
	#loop through command matrix and execute commands
	 foreach my $pcmd (@printCmds) { 
		eval $pcmd;
	 };
	
	
	# switch($type){
		# case "plot"{
			# for (my $i=0; $i<$numCmds;$i++) {
				# unless ($tazCmds[$i] eq "")	{
					# #Send CMD to taz
					# taz_writeReady($tazCmds[$i]."\n");
				# }
			# }
		
		# }#end case
		# case "constPres" {
			# for (my $i=1; $i<=$numCmds;$i++) {
		
			# #Send CMD to taz
			# taz_writeReady($tazCmds[$i]."\n");
			# #Send to Extruder
			# ext_dlCMD("DI ","");
			# }
		# }#end case
		# case "varPres" {
		
		# }#end case
		# else{
			# print("Error - IO_executeFilePrint");
		# }#end else
	
	
	# }#end switch
	
}#End sub

#Handles Common hardware input dialogues/actions for input switch cases
#RESERVED switch cases: STOP; clean,0; lift,1; ext,2; last,/;m,.,s,x,z,a, w
sub IO_hardwareInputs{
	my $input = shift;
	switch ($input) { #T2 Switch
		case "STOP" { #send emergency stop (requires physical reset)
			taz_write("M112\n");
		}
		case ["clean","0"] { #Lifts up and then lowers back slowly
			taz_writeReady("M117 Cleaning up...\n"); #LCD Status Message					
			taz_writeReady("G91\n"); #Relative Positioning
			taz_writeReady("G1 F1000 Z20\n"); #Lift up by 20
				
			#prompt user for when done cleaning
			#Ask if okay					
			print("Lower? Y/N: ");
			my $in = <STDIN>; chomp($in);
			#if yes, continue
			if ($in eq "Y") {
				taz_writeReady("G1 F1000 Z-10\n"); #down 
				taz_writeReady("G1 F100 Z-7\n"); #down slower
				taz_writeReady("G1 F60 Z-3\n"); #down slowest
			}		
		}#end T2 case
		
		
		case ["lift","1"] { #Lifts up
			taz_writeReady("M117 Lifting up...\n"); #LCD Status Message
			#taz_readLine();							
			taz_writeReady("G91\n"); #Relative Positioning
			#taz_readLine();		
			taz_writeReady("G1 F1000 Z20\n"); #Lift up by 20
			#taz_readLine();				
		}#end T2 case
		
		case ["ext","2"] { #Manual control of extruder
			$input = "";	
			my $done = 0;
			until ($done==1) {
				print("WARNING: Sending commands directly to UltimusV\nq to quit\nDI to dispense\nEnter Command string[,] data string: ");					
				$input = <STDIN>;
				chomp($input);
				switch ($input) {
					case "q" {
						$done = 1;
					}
					case "DI" {
						ext_dlCMD("DI ","");
					}
					else {
						my @cmds = split /,/,$input;	
						my $success = ext_dlCMD($cmds[0],$cmds[1]);
						if ($success ==0){
							print("Error sending command to ultimus\n");
						}
					}#end T3case
				}#end T3switch
			}#end T3loop
		}#end T2case
		
		case ["last","/"] {#Submit last command again
			if ($lastCmd eq ""){
				print("\tERROR: Last Command Empty\n");
			}
			else{
				taz_writeReady($lastCmd."\n");
			}												
		}#end T2case
		
		case ["m"] {#Save a command
			print("\tEnter (GCODE) command: ");					
			$savedCmd = <STDIN>; #pull input text
			chomp($savedCmd); #remove spaces	
												
		}#end T2case
		
		case ["."] {#Run saved command
			if ($savedCmd eq ""){
				print("\tERROR: Saved Command Empty\n");
			}
			else{
				taz_writeReady($savedCmd."\n");
			}												
		}#end T2case
		
		#Jog directions
		case ["s"] {#Jog down
			taz_writeReady("G0 Z-1\n");
														
		}#end T2case
		
		case ["x"] {#Jog down SMALL
			taz_writeReady("G0 Z-0.1\n");
		}#end T2case
		
		case ["z"] {#Jog down SMALL
			taz_writeReady("G0 Z-0.01\n");
														
		}#end T2case
		case ["w"] {#Jog up
			taz_writeReady("G0 Z1\n");
														
		}#end T2case
	
		case ["a"] {#Jog left
			taz_writeReady("G0 X-1\n");
														
		}#end T2case
		
		case ["d"] {#Jog right
			taz_writeReady("G0 X1\n");
														
		}#end T2case
		
		case ["r"] {#Jog Y-
			taz_writeReady("G0 Y-1\n");
														
		}#end T2case
		
		case ["f"] {#Jog Y+
			taz_writeReady("G0 Y1\n");
														
		}#end T2case
		
		else {#didnt match any of the common functions
			return 0;
		}
	}#end T2 switch
	return 1; #Matched one of the above
}

#Updates commonhardware hash
sub IO_hardwareInputsRefresh{
	%HardwareCommon = 
			("STOP" => "Emergency STOP",
			"/" => "Repeat Last: ".$lastCmd,
			"m" => "Enter Saved Command",
			"." => "Run Saved Command: ".$savedCmd,
			"a,d;r,f;w,s;x,z" => "Jog (X; Y; Z; Zsmall)",
			"(0) clean" => "Lift up 20 mm, lower on cmd",
			"(1) lift" => "Lift up 20 mm",
			"(2) ext" => "Send cmd to extruder");
}

#Lifts nozzle and prompts for lower
sub IO_clean{
	#Lifts up and then lowers back slowly
	taz_writeReady("M117 Cleaning up...\n"); #LCD Status Message						
	taz_writeReady("G91\n"); #Relative Positioning	
	taz_writeReady("G1 F1000 Z20\n"); #Lift up by 20	
	#prompt user for when done cleaning
	#Ask if home sequence okay before proceeding						
	print("Lower? Y/N: ");
	my $in = <STDIN>; chomp($in);
	#if yes, continue
	if ($in eq "Y") {
		taz_writeReady("G1 F1000 Z-10\n"); #down 
		taz_writeReady("G1 F100 Z-7\n"); #down slower
		taz_writeReady("G1 F60 Z-3\n"); #down slowest
	}	
}

#Transforms Gcode extruder commands to dispense commands
sub IO_trsExt {


}

#Simple helper for getting keyboard input
#Param [String for Prompt]
#Return Chomped input string
sub IO_getStdInput{
	print(shift);				
	$input = <STDIN>; #pull input
	chomp($input); #eliminate spaces
	return $input;
}
	

sub IO_dispFile {	
	if (open(my $fh, '<:encoding(UTF-8)', $gFile)) {
	  while (my $row = <$fh>) {
		 chomp $row;
		 print "$row\n"; #
	  }
	} else {
	  print "Could not open file '$gFile' $!";
	}
}

#Read in from text file
#Return arrays of taz and extruder commands
sub IO_readGFile {	
	my @readLines;	
	if (open(my $fh, '<:encoding(UTF-8)', $gFile)) {
		#Read in lines to readLine array		
		while (my $row = <$fh>) {
			chomp $row; #remove newlines
			$row =~ s/\(penetrate\)/ /ig; #Remove inline comments from inkscape
			#Throw out GCODE comments and non-motion (G) cmds based on first character
		 	if (substr($row,0,1) eq "G") 
			{
				push(@readLines, $row);	
			}
		}
		##for testing
		#	foreach (@readLines) {
	 	#		 print "$_\n";
		#	}

		return \@readLines;
	} #file not found
	else {
		print "Could not open file '$gFile' $!";
	}
}

#################################
###Utility Processing Subroutines
#################################
   
#Utility
sub u_lu_trim { my $s = shift; $s =~ s/^\s+//;       return $s };
sub u_ru_trim { my $s = shift; $s =~ s/\s+$//;       return $s };
sub u_trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s };

#Take pressure string, do math, then return pressure string
	#Param 1 String Input pressure string kPa format 0000
	#Param 2 String Input operation
	#Param 3 Value for increment/product (negative for decrease)
sub u_presMod {
	my ($input,$math, $val) = @_; #params
	#convert input string into value
	$input = $input/10;
	my $calc = 0;
	switch ($math){
		case "+"{
			$calc = $input+$val;
		}
		case "*"{
			$calc = $input*$val;
		}
	}
	#Convert pressure to string and return
	my $out = sprintf("%05.1f",$calc);
	$out =~ s/[.,]//g;
	return $out;
}
#Take speed literal, do math, then return speed string
	#Param 1 literal Input speed
	#Param 2 String Input operation
	#Param 3 Value for increment/product (negative for decrease)
sub u_vMod {
	my ($input,$math, $val) = @_; #params
	my $calc = 0;
	switch ($math){
		case "+"{
			$calc = $input+$val;
		}
		case "*"{
			$calc = $input*$val;
		}
	}
	#return
	return $calc;
}
#Print in from text file

#Simple helper to print array contents
sub u_printArray {
	foreach (@_) {
	 	 print "$_\n";
	}

}

################################################################################################
#  Extruder Subroutines
################################################################################################
#Creates SerialPort object for the extruder
sub ext_init {
	  
	#Create new serialport object	
	$ext_dev = new Device::SerialPort($ext_prt, 1);
	
	print("Connecting to UltimusV...\n");
	#Check if object could be created, else exit.
	if (!defined($ext_dev)) {
		print "ERROR - couldn't get extruder serial port - $!\n";
		exit(1);
	}

	#SerialPort Parameters
	$ext_dev->baudrate(115200);
	$ext_dev->parity("none");
	$ext_dev->databits(8);
	$ext_dev->stopbits(1);
	$ext_dev->handshake("none");
	$ext_dev->stty_icrnl(0);
	$ext_dev->stty_ocrnl(0);
	$ext_dev->stty_onlcr(0);
	$ext_dev->stty_opost(0);
	$ext_dev->write_settings;
	$ext_dev->read_char_time(0); # return immed. if no chars
	sleep(1);
	$ext_dev->purge_rx; #empties receiver
	print("Connected to UltimusV!\n");

	#Put Extruder into steady mode
	ext_dlCMD("MT  ","");
	#Set dispense units
	ext_dlCMD("E6  ","02"); #00psi, 01Bar, 02kPa
	#Set vacuum units
	ext_dlCMD("E7  ","00"); #00psi 01in.H2O 02in.Hg 03mmHg 04Torr
}

#Stops the serialport and closes the device
sub ext_stop 
{
	print("Closing UltimusV...\n");	
	ext_write($ExCmd2Char{EOT});
	sleep(3);
	undef $ext_dev;
	print("Closed UltimusV!\n");	
}

#Writes scalar value to extruder
	#param scalar to write
sub ext_write {
	$ext_dev->write($_[0]);
}

#Reads in a character from extruder
	#Param: Coimmand character to compare read in character to (optional)
	#Returns character read in as character
	#Times out after .25 seconds, returns "TIMEOUT"
sub ext_read {
	#read response	
	my $cnt = 0; #number of characters rcvd
	my $charIn = ""; #read in string
	my $tEnd = time()+ .25;	
	#read in until no longer empty or timeout
	while ($cnt == 0 && time() < $tEnd) {
		($cnt, $charIn) = $ext_dev->read(1);
	}
	
	#return timeout if timed out before receiving characters
	if ($cnt == 0) {
		return "TIMEOUT";
	}
	
	#Optionally compare to command character
	if (defined($_[0])) {
		#Check if expected code received
		unless ($ExChar2Cmd{$charIn} eq $_[0]){
			print("\tError: Unexpected input from Ultimus\n");
			return "-1";
		}
	}
	return $charIn;	
}

#Reads in a line of characters from extruder
	#Returns String of characters read in before read timeout
sub ext_readLine {
	my $charIn = "";
	my $lineIn = "";
	while ($charIn ne "TIMEOUT") {
		$lineIn .= $charIn;		
		$charIn = ext_read();
	}
	
	if ($verbose) {
		if ($lineIn eq "") {
			print("\tEmpty Line read from extruder\n");
		}
	}
	return $lineIn;
}

#Sends ENQ and chrecks if receives acknowledgement
	#Return 
sub ext_handshake {
	if ($verbose){
		print("\tAttempting handshake with UltimusV...\n");
	}	
	
	#send ENQ
	ext_write($ExCmd2Char{"ENQ"});	
	#read response	
	my $in = ext_read("ACK");
	
	#if failed, return -1
	if ($in eq "-1"){
		if ($verbose){
			print("\tHandshake failed!\n");
		}
		return -1;
	}
	
	#else report success
	if ($verbose){
		print("\tHandshake succesful!\n");
	}	
	return 1;
}

#Converts ASCII letter to hex String
sub u_ASCII2HexStr{
		#ASCII to decimal
		my $dec = ord($_[0]);	
		#decimal to hex
		my $hex = (sprintf("0x%X", $dec));
		return $hex;
}


#Converts ASCII letter to hex scalar
sub u_ASCII2Hex{
		#ASCII to decimal
		my $dec = ord($_[0]);	
		#decimal to hex
		my $hex = hex(sprintf("0x%X", $dec));
		return $hex;
}

#Calculates checksum for UltimusV and returns as string of length 2
	#Logic: subtract hex value from 0 and output least significant byte
	#param String to operate  on
	#returns $hexSum String of length 2
sub ext_calcChecksum{
	my $checktotal = 0;
	my @checkArray = split(//, $_[0]);
	#for each value in input args
	foreach (@checkArray){
		$checktotal-=u_ASCII2Hex($_);
	}
	#convert to hex string
	my $hexTotal = sprintf("0x%X", $checktotal);
	#take last two digits
	my $hexSum = substr($hexTotal,-2);
	return $hexSum;
}

#Sends dispense command to extruder
sub ext_dispense{
	ext_dlCMD("DI ","");
};


#Sends a download command and interprets acknowledgement before sending EOT returns 0 for fail, 1 for success
#parameter: download command name string, download command Data string
sub ext_dlCMD{
	$ext_dev->purge_rx; #empty receive buffer
	
	#package command string	
	my $toSend = ext_pack($_[0],$_[1]);
	
	my $done = 1;
	
	#Enq -> ACK
	unless (ext_handshake()) {$done = 0};
		
	#send command packet
	unless (ext_write($toSend)) {$done = 0};
	
	#Receive response
	my $received = ext_readLine();	
	chomp $received;	
	
	#end Transmission
	ext_write($ExCmd2Char{"EOT"});

	#Unpack Response
	(my $CMDStr, my $CMDVal) = ext_unpack($received);
	
	if ($CMDStr eq "A0"){
		return 1;
		if ($verbose){
			print("\tCMD Packet Sent successfully\n");	
		}
	}
	else {
		$done = 0;
	}
	
	unless ($done) {
		if ($verbose){
			print("\tSending CMD Packet Unsuccessful\n");	
		}
	}
	return ($done);
}

#Packs a command packet based on a particular command string, calculating all values and appending STX, ETX characters
#param Input Command Name String, Command Data String
#returns the packaged String to send
sub ext_pack {
	#Proper syntax of command packet: STX + DataString + Checksum + ETX
	#Datastring = NumBytes + CommandName + Command Data
	my $CMDString = ($_[0] . $_[1]);
	#Create NumBytesField
	#hex number of format 0x##	
	my $nBytes = sprintf("0x%X", length($CMDString));
	$nBytes = substr($nBytes,2);
	#Force to 2 digits (e.g., 08 not 8)
	if (length($nBytes) == 1){
		$nBytes = "0".$nBytes;
	}	
	
	
	#create Data string
	my $dataString = $nBytes . $CMDString;

	#Calculate Checksum
	my $checkSum = ext_calcChecksum($dataString);
	#TODO add bed temp...
	#Package
	my $CMDPacket = $ExCmd2Char{"STX"}.$dataString.$checkSum.$ExCmd2Char{"ETX"};
	return $CMDPacket;
}

#Unpacks a command packet based on a particular command string to obtain the command name string and command value
#returns the command name string and command value
sub ext_unpack {
	#Proper syntax of command packet: STX + DataString + Checksum + ETX
	#Datastring = NumBytes + CommandName + Command Data
	my $input = $_[0];	
	chomp($input);
	
	#Remove STX, numBytes, remove Checksum,ETX
	my $DataString = substr($input,3,-3);
	
	my $CMDStr = substr($DataString,0,4);
	my $CMDVal = "";
	
	#Unless it is short command (A0,A2) with no data, evaluate data string	
	unless (length($DataString)<5) {	
		my $CMDVal = substr($DataString,4);
	}
	#return strings	
	return ($CMDStr,$CMDVal);
}


################################################################################################
#  taz Subroutines
################################################################################################

#Creates the serialport object for taz6, cleans input buffer
sub taz_init {
	print("Connecting to Taz6...\n");
	
	#Set up USB Connection
	$taz_dev = Device::SerialPort->new("/dev/ttyACM0")||die;
    $taz_dev->baudrate(115200);
	$taz_dev->databits(8);
	$taz_dev->parity("none");
	$taz_dev->stopbits(1);

	##Clear initial input
	
	#to clear strange unknown text in output buffer????
	$taz_dev->write("\n");
	
	#strategy: keep reading until more than 1 sec from last input
	my $tEnd = time()+1;
	until (time() > $tEnd) { 
		my $c = $taz_dev->lookfor(); # get the next element
		unless ($c eq "") {
			$tEnd = time()+1;
			# print input data
			if ($verbose) {print "\tInitial Read: ".$c."\n";} 
		}
	}
	#Turn off taz printhead fans
	taz_writeReady("M107\n");
	#taz_readLine();
	
	print("Connected to Taz6!\n");
}

#Stops the serialport and closes the device
sub taz_stop {
	print("Closing Taz6...\n");		
	sleep(2);
	taz_writeReady("M140 S20\n"); #set temp to 20C
	#taz_readLine();
	undef $taz_dev;
	print("Closed Taz6!\n");	
}

#Sends a command to the printer
sub taz_write {
	$taz_dev->write(@_);
	if($verbose){	
		print("\tCommand sent: " . $_[0]);
	}
}

#Reads until times out (input) then Returns input
sub taz_readTime {
	my $input = ""; #input string
	my $in = ""; #read in
	my $timeout = $_[0]; #timout timer
	my $tEnd = time()+$timeout; 
	
   #Reads input until timeout
	until (time() > $tEnd) { 
		$in = $taz_dev->lookfor();
		if ($in ne ""){
			$input .= $in;
		}	
	}	
   chomp($input);  #removes any newlines
	return ($input);
}

#Returns line read in from printer. Errors if "ok" not received or times out.
sub taz_readLine {
	
	my $input = taz_readTime(.5);
	#Handles unexpected input 
	#TODO Revisit taz error handling
	if (length($input)!=9&&length($input)!=8&&$verbose){
			#print("taz6 Error... Timed out or Error received.\n");
			print("\tReceived    : ". $input."\n");
	}

	if ($verbose) {
		print("\tReceived    : " .$input ."\n"); 
	}
   return($input); #return full input string
}

#Checks if taz is ready to receive new command by Looking for "ok" in input
sub taz_waitReady {
	my $ready = 0;
	my $input = "";
	
	my $i=0; #number of loop increments

	until($ready){
		$i++;		
		$input = taz_readTime(.05); #read buffer
		
		if ($i%10==0&&$verbose){ #Printing status update every 5 increments
			print("\tWaiting on taz... ... ...\n");
		}
		
		if (index($input,"ok")!=-1){
			$ready = 1;
		}			
	}
	print("\tReceived: ".$input."\n");
	return $input;
}

#Writes when ready, param: command string
sub taz_writeReady {
	my $inp = shift;
	taz_write($inp);
	taz_waitReady();	
}

#Gets the current position (absolute) from taz and returns XYZ coordinates
#Returns array with X,Y,Z absolute positions
sub taz_getAbsPosXY{
	print("\t");
	taz_write("M114\n");
	print("\t");
	my $M114Call = taz_waitReady();
	my @M114Split = split / /, $M114Call;
	my $X = substr($M114Split[0],2);
	my $Y = substr($M114Split[1],2);
	return ($X, $Y);
}

#Moves carriage to provided absolute X,Y coordinates
#Input Array of absolute X,Y coordinates
sub taz_goToXY{
	#pull input args
	my ($Xabs, $Yabs) = @_;
	
	#Set to absolute positioning
	taz_writeReady("G90\n");
	
	#Move to input position at high speed
	taz_writeReady("G1 F2000 X" . $Xabs . " Y" . $Yabs ."\n");

	#Return to relative positioning
	taz_writeReady("G91\n");
}
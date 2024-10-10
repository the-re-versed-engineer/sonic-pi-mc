#!/bin/bash

#Variables
serverPath="$(dirname $(realpath $0))"
serverName="$(basename "$serverPath")"

#Functions
PressAnyKeyToContinue () {
	read -r -n 1 -p "Press any key to continue..."
	clear
}

ChooseDirectory () { #user input for a generic chosen directory that can be used by the function that just called this one
	chosenDirectory=""
	while [ "$chosenDirectory" == "" ]; do
		read -r -p "Directory: " chosenDirectory
		echo
		ConfirmUserInput
		if [ "$userConfirmation" == "n" ]; then
			clear
			echo "$chosenDirectory" "Not Confirmed. Re-enter path to directory."
			chosenDirectory=""
		elif [ ! -d "$chosenDirectory" ]; then
			clear
			echo "Directory:" "$chosenDirectory" "Was NOT found. Please retype the full path to directory."    
			chosenDirectory=""
		fi
	done
} #end of ChooseGuestSourceDirectory

ConfirmUserInput () {
	userConfirmation=""
	while [ "$userConfirmation" == "" ]; do
		read -r -n 1 -p "Is this correct? [Y/n]" userConfirmation
		echo
		case "$userConfirmation" in
			Y | y |"")  break ;;
			N | n ) break ;;
			[!YyNn])  clear ; echo "Input Not recognized. Please reconfirm."; userConfirmation="" ;;
		esac
	done
} # end of ConfirmUserInput

GenericSelectLoop () { #input arguments to function become the items to select (separated by space)
PS3="Select via number: "
selectedItem=""
select selectedItem in "$@" ; do
	case "$selectedItem" in
		"$selectedItem") 
			if [ "$selectedItem" != "" ]; then
				echo "$selectedItem"
				break
			else
				echo "Selection not on list/not recognized."
			fi
		;;
	esac
done
}

ShutdownFunc () {
	#send stop to mc server input
	echo 'stop' >&"${COPROC[1]}"
	#Send a terminate signal to all background jobs
	kill -SIGTERM $(echo $(jobs -p))
	#wait for everything in the background to close
	wait
	#close file descriptors for in_pipe
	exec {in_pipe}>&-
	exec {in_pipe}<&-
	#close file descriptors for out_pipe
	exec {out_pipe}>&-
	exec {out_pipe}<&-
	#close file descriptors for in_cp_fd
	exec {in_cp_fd}>&-
	exec {in_cp_fd}<&-
	#close file descriptors for out_cp_fd
	exec {out_cp_fd}>&-
	exec {out_cp_fd}<&-
	#remove tmpdir and exit script
	rm -fr "$tmpDir"
	exit
}

EditServerProperty () {
	#$1=property-to-edit
	#$2=new-property-value
	sed -i "s/$1=.*/$1=$2/" server.properties
}

StartServer () { #--start #$2=-p/-ip/pw #$3=port/ip		#$last_Arg=--setup/--nogui
	cd "$serverPath" || exit 1
	#user can change port, ip, or worldname
	if [ "$2" == "-p" ]; then
		EditServerProperty "server-port" "$3"
	elif [ "$2" == "-ip" ]; then
		EditServerProperty "server-ip" "$3"
	elif [ "$2" == "-w" ]; then
	EditServerProperty "level-name" "$3"
	fi
	
	if [ "$4" == "-p" ]; then
		EditServerProperty "server-port" "$5"
	elif [ "$4" == "-ip" ]; then
		EditServerProperty "server-ip" "$5"
	elif [ "$4" == "-w" ]; then
	EditServerProperty "level-name" "$5"
	fi
	
	if [ "$6" == "-p" ]; then
		EditServerProperty "server-port" "$7"
	elif [ "$6" == "-ip" ]; then
		EditServerProperty "server-ip" "$7"
	elif [ "$6" == "-w" ]; then
	EditServerProperty "level-name" "$7"
	fi
	
	#export main/starting/parent pid
	export serverStarterPid="$$"
	#assign variables
	tmpDir="$serverPath/tmp_pipes"
	#setup folders and pipes
	cd "$serverPath" || exit 1
	mkdir 'tmp_pipes'
	cd "$tmpDir"
	mkfifo in_pipe
	mkfifo out_pipe
	exec {in_pipe}<>in_pipe
	exec {out_pipe}<>out_pipe
	cd "$serverPath"
	#start the server in a coprocess
	if [ "${!#}" == "--nogui" ] || [ "${!#}" == "--setup" ] ; then
		coproc (java -jar server.jar nogui) >&"${out_pipe}"
	else
		coproc (java -jar server.jar) >&"${out_pipe}"
	fi
	#export coproc in/out FD as variables
	export in_cp_fd="${COPROC[1]}"
	export out_cp_fd="${COPROC[0]}"
	#point coproc in/out so separate FD variables
	exec {in_cp_fd}<&"${COPROC[1]}"
	exec {out_cp_fd}<&"${COPROC[0]}"
	#export pipe in/out FD as variables
	export in_pipe_fd="${in_pipe}"
	export out_pipe_fd="${out_pipe}"
	#clone output of out_cp_fd to out_pipe fd
	exec {out_cp_fd}>&"${out_pipe}" 
	
 	#if the last argument is --setup it will shut itself off after the world is done loading
	if [ "${!#}" == "--setup" ] ; then
		while read coproc_output <&"${out_cp_fd}"; do
			if echo "$coproc_output" | grep -e "Done"; then
				echo "stop" > tmp_pipes/in_pipe
			fi
		done & #bg job
	else #reads output of coproc and sends to stdout
		while read coproc_output <&"${out_cp_fd}"; do
			echo "$coproc_output" >&1
		done & #bg job
	fi

	#reads input to in_pipe and sends to coproc input
	while read fifo_input <&"${in_pipe_fd}"; do 
		echo "$fifo_input" >&"${in_cp_fd}"
		if [ "$fifo_input" == "stop" ]; then
			kill -SIGINT "$serverStarterPid"
		fi
	done & #bg job
	
	#FORGROUND WHILE LOOP#read user input and send it to minecraft server input#Anymore background jobs should be put before this loop and trap#
	#Ctrl-C interupt trap
	trap 'ShutdownFunc' SIGINT SIGTERM
	while true; do
		read server_out
		echo $server_out >&"${COPROC[1]}"
	done
}

BackupWorld () { #--backup-world
	todaysDate="$(date --rfc-3339=date)"
	cd "$serverPath" || exit 1
	echo "Enter the name of the world(folder) to backup."
	read -p "World Name: " worldName
	cd "$worldName"
	tar -czf "$worldName"-"$todaysDate".tar.gz *
	mv "$worldName"-"$todaysDate".tar.gz "$serverPath"
}

BackupServer () { #--backup-server
todaysDate="$(date --rfc-3339=date)"
cd "$serverPath" || exit 1
tar -czf "$serverName"-"$todaysDate".tar.gz *
}

CreateNewWorld () { #--create-new-world
	cd "$serverPath" || exit 1
	if [ "$1" == "" ]; then
		echo "Enter the name for the new world."
		read -p "World Name: " worldName
		EditServerProperty "level-name" "$worldName"
	else
		EditServerProperty "level-name" "$1"
	fi
	if [ "$2" == "" ]; then
		echo "Sellect which type of world you would like:"
		echo
		worldType="$(GenericSelectLoop normal flat large_biomes single_biome_surface amplified)"
		EditServerProperty "level-type" "minecraft\:$worldType"
	else
		EditServerProperty "level-type" "minecraft\:$2"
	fi
StartServer --setup
}

HelpAndInfo () {
echo "####################### HELP #######################"
echo "This script is inteded to be placed (and used) with the server folder."
echo "It should not matter what version of minecraft you are using or whether it is modded or not."
echo "This script works by creating a file that can be written to by sonic-pi (or another program.)"
echo "The script then writes what was sent to the in_pipe file to the servers standard input."
echo "This file it temporary and is not contained on he hard drive (to avoid lots read/write operations.)"
echo "It will be located in the server folder in a new folder labeled tmp_pipes"
echo ""
echo ""
echo "When using sonic-pi, you can write to the in_pipe file within the tmp_pipes folder from multiple threads at once."
echo 'Since the end point is the MC servers standrd input, the in_pipe file will expecting a TEXT string with a \n to end the input.'
echo "Sonic-pi uses the Ruby laguage and most buitin commands seem to work (as far as i have tested[not very far]) in the sonic-pi interface."
echo ""
echo ""
echo "REFERENCES:"
echo "https://sonic-pi.net/tutorial.html"
echo "https://ruby-doc.org/docs/ruby-doc-bundle/Manual/man-1.4/function.html"
echo ""
echo ""
echo "OPTIONS/FLAGS"
echo ""
echo "--start"
echo "--start: Will start the server witht the in/out pipes created in a folder named tmp_pipes"
echo "(OPTIONALLY) After --start, as the last argument you can give either --setup or --nogui"
echo ""
echo "--startup will not display the output of the server to the AND will not start the gui."
echo "It will instead wait for the world to fully load then shut itself down."
echo ""
echo "--nogui will still display the output to the terminal but it will not open the gui"
echo ""
echo "After --start but before the final arg --setup/--nogui."
echo "-p <Port>"
echo "-ip <IP Address>"
echo "-w <World Name>"
echo "(order does not matter for these)"
echo ""
echo "EXAMPLEs:"
echo "./SCRIPTNAME --start --setup"
echo "./SCRIPTNAME --start -w world_1 -ip 127.0.0.1 --nogui"
echo "./SCRIPTNAME --start -p 25565 -ip 127.0.0.1 -w worldname --nogui"
echo "./SCRIPTNAME --start -ip 127.0.0.1 -w worldname -p 25565"
echo ""
echo ""
echo "--create-new-world"
echo "--create-new-world: will create a new world in the server folder"
echo "(OPTIONALLY) After --create-new-world you can include a 'name' in quotes and the world will be given than name."
echo "(Only 1 arg after --create-new-world 'the name' or leave it blank.)"
echo "If no name is included the user will be prompted for one."
echo ""
echo ""
echo "--backup-world"
echo "--backup-world: Backs up the world folder and its contents with the date in the name. It will be located in the server folder."
echo "No additional arguments."
echo ""
echo "--backup-server"
echo "--backup-server: Backs up the server files and folders with the date in the name. It will be located in the server folder itself."
echo "No additional arguments."
echo ""
echo ""
echo "Close the server with Ctrl-C"
}

#main args decider
if [ "$1" == "--start" ]; then
	StartServer $@
elif [ "$1" == "--backup-world" ]; then
	BackupWorld
elif [ "$1" == "--backup-server" ]; then
	BackupServer
elif [ "$1" == "--create-new-world" ] && [ ! "$3" == "" ]; then
	CreateNewWorld $2 $3
elif [ "$1" == "--create-new-world" ] && [ "$3" == "" ]; then
	CreateNewWorld $2
elif [ "$1" == "--help" ]; then
	HelpAndInfo
else
	HelpAndInfo
fi

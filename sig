#!/bin/env -S gawk -f

# Wrapper for signal-cli, adding convenience and color
# Cam Webb. See <https://github.com/camwebb/signal-cli-wrapper>
# License: GNU GPLv3. See LICENSE file.

# Installation:
#   1) Make this script executable
#   2) This script and signal-cli must be in your shell's $PATH
#   3) Make sure "scw_config.awk" is in a directory present in environment
#      variable $AWKPATH

@include "scw_config.awk"

BEGIN{

  # Setup
  config()
  proc_nums()

  # logfile
  LOG = SCLI "msgs"
  
  # logfile date format. Note the three extra 0s
  DATE = strftime("%s000 (%Y-%m-%dT%H:%M:00.000Z)")
  
  USAGE = "Usage: sig ...\n"                                               \
    "           snd NAME \"MSG\" = Send (use \"...\"\\!\\!\"...\" for" \
    " multiple !)\n"                                                   \
    "           rcv            = Receive\n"                            \
    "           cnv NAME       = Conversation\n"                       \
    "           log            = See log\n"                            \
    "           ids            = Get contacts from server\n"           \
    "           num            = List contacts in config\n"            \
    "           gls            = List groups\n"                        \
    "           gnu DESC       = New group (v2 GROUPS CURRENTLY NOT WORKING)\n"\
    "           gad GNAME NAME = Add person to group\n"                \
    "           glv GNAME      = Leave group\n"                        \
    "           ckn NUM        = Check NUM for Signal\n"               \
    "           cfg            = Edit config file\n"                   \
    "           cli            = Show signal-cli usage\n"              \
    "           new            = See new messages"

  # Begin tests for actions
  
  # Get the registered numbers
  if ((ARGV[1] == "ids") && \
      (ARGC == 2)) {
    cmd = "signal-cli -u " MYNUM " listIdentities"
    while ((cmd | getline) > 0) {
      if (iNUM[gensub(/:$/,"","G",$1)])
        list[iNUM[gensub(/:$/,"","G",$1)]]++
      else
        list[gensub(/:$/,"","G",$1)]++
    }
    PROCINFO["sorted_in"] = "@ind_str_asc"
    for (i in list)
      print "  " i "  (" list[i] " devices)"
  }

  # Get the user names/numbers
  if ((ARGV[1] == "num") &&                     \
      (ARGC == 2)) {
    print "Short names of people and groups in config file:"
    PROCINFO["sorted_in"] = "@ind_str_asc"
    for (i in NUM)
      printf "  %-10s : %s\n",  i , NUM[i]
  }

  # Get the latest messages and write to stdout and to logfile
  else if ((ARGV[1] ~ /(rcv|new)/) &&           \
           (ARGC == 2)) {
    err = system("signal-cli -u " MYNUM " receive | tee -a " LOG)
    if (err) {
      print "Receiving failed" > "/dev/stderr"
      exit 1
    }

    # list new recieved messages since last time this was run
    if (ARGV[1] == "new") {
      getline OLDLINES < (SCLI "oldlines")
      RS=""
      FS="\n"
      while (( getline < LOG ) > 0) {
        if (++l <= OLDLINES)
          continue
        sender = body = ""
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^Sender:/)
            sender = gensub(/^[^+]+(\+[0-9]+) .*$/,"\\1","G",$i)
          else if (($i ~ /^Body:/) && sender) {
            if (iNUM[sender])
              list[iNUM[sender]]++
            else
              list[sender]++
          }
        }
      }
    
      PROCINFO["sorted_in"] = "@ind_str_asc"
      if (isarray(list)) {
        print "New messages from:"
        for (i in list)
          print "  " i " (" list[i] ")"
      }
      else
        print "No new messages"
      
      # reset
      print l > (SCLI "oldlines")
    }
  }
  
  # read the logfile, substituting names for numbers
  else if ((ARGV[1] == "log") &&                \
           (ARGC == 2)) {
    "mktemp" | getline TMPLOG
    while (( getline < LOG ) > 0) {
      for (i in iNUM)
        gsub(gensub(/\+/,"\\\\+","G",i),("{" iNUM[i] "}"),$0)
      print $0 >> TMPLOG
    }
    system("less +G " TMPLOG)
  }
  
  # Send a message to <name> and write to logfile
  else if ((ARGV[1] == "snd") &&                \
           (ARGC == 4) &&                       \
           (NUM[ARGV[2]])) {
    
    err = system("signal-cli -u " MYNUM " send " NUM[ARGV[2]]   \
                 " -m \"" ARGV[3] "\"")
    if (err) {
      print "Sending failed" > "/dev/stderr"
      exit 1
    }

    print "Envelope from: " MYNUM " (device: 1)\n"  \
          "Timestamp: " DATE "\n" \
          "Sender: " MYNUM " (device: 1)\n" \
          "To: " NUM[ARGV[2]] "\n" \
          "Body: " ARGV[3] "\n" >> LOG
  }
  
  # Create a conversation from the logfile
  else if ((ARGV[1] == "cnv") &&                \
           (ARGC == 3) &&                       \
           (NUM[ARGV[2]])) {
    RS=""
    FS="\n"
    Width = 55
    name = ARGV[2]

    while (( getline < LOG ) > 0) {
      # Parse log - starting signal-cli 0.7.2-1 not expecting any particular
      #   order of log fields
      sender = sent_to = ts = body = att = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^Sender:/)
          # complicated, because if the number is in Signal 'contacts' then
          #   the contact name appears before the number
          sender = gensub(/^[^+]+(\+[0-9]+).*$/,"\\1","G",$i)
        else if ($i ~ /^To:/)
          sent_to = gensub(/^[^+]+(\+[0-9]+).*$/,"\\1","G",$i)
        else if ($i ~ /^Timestamp:/)
          ts = substr($i,12,10)
        else if ($i ~ /^Body:/) {
          body = substr($i, 7)
          # multi line - tricky
          k = i + 1
          while ((k <= NF) &&                       \
                 ($k !~ /^[A-Z][a-z]+:/) &&         \
                 ($k !~ /^Profile key update/)) {
            body = body " // " $k
            k++
          }
        }
        else if ($i ~ /Stored plaintext/)
          body = body " [ ATT:  ~/.local/share/signal-cli/attachments/" \
             gensub(/.*\/attachments\/(.*)$/,"\\1","G",$i) " ]"
      }

      # print "{" sender "}{" sent_to "}{" body "}"
      # for each log entry, is it a sent to person?
      # TODO, separate out Group messages
      if ((sent_to == NUM[name]) && body)
        format_line(body, (sprintf("%*s", length(name), " ") "<< "), "10", ts)
      # sent from person?
      else if ((sender == NUM[name]) && body)
          format_line(body, (name " : "), "11", ts)
      
      # # sent to group?
      # else if ($1 ~ ("Group sent to: " name))
      #   format_line(substr($3,7), (sprintf("%*s", length(name), " ") "<< "), \
      #        "10", substr($2,12,10))
      # # sent from group friend
      # else if (($4 ~ ("Sender:")) && ($6 ~ /^Body/) && ($8 ~ name))
      #   format_line(substr($6,7), (gensub(/ \(dev.*/,"","G", substr($4,8)) \
      #     " : "),                                                     \
      #        "11", substr($2,12,10))
    }
  }

  # Test for user
  else if ((ARGV[1] == "ckn") &&                \
           (ARGC == 3) &&                       \
           (ARGV[2] ~ /\+[0-9]+/)) {
    print "Testing for a Signal user at " ARGV[2]
    err = system("signal-cli -u " MYNUM " send " ARGV[2]            \
                 " -m 'Testing if you use Signal' &> /dev/null")
    if (err)
      print "... User does not have a Signal account"
    else
      print "... User has a Signal account (Message sent was "  \
        "'Testing if you use Signal')"
  }

  # list groups
  else if (ARGV[1] == "gls") {
    cmd = "signal-cli -u " MYNUM " listGroups -d"
    while ((cmd | getline) > 0) {
      for (i in iNUM)
        gsub(gensub(/\+/,"\\\\+","G",i),("{" iNUM[i] "}"),$0)
      print $0
    }
  }

  # Leave group
  else if ((ARGV[1] == "glv") && \
           (NUM[ARGV[2]])) {
    err = system("signal-cli -u " MYNUM " quitGroup -g '" NUM[ARGV[2]] "'")
    if (err)
      print "... Error. Could not leave group."
    else
      print "... Left group"
  }

  # # New group
  # else if ((ARGV[1] == "gnu") &&                \
  #          (ARGC == 3)) {
  #   err = system("signal-cli -u " MYNUM " updateGroup -n '" ARGV[2] "'")
  #   if (err)
  #     print "... Error. Could not create group."
  #   else
  #     print "... Group created"
  #   # 2021-01-14:
  #   # ~> sg gnu 'test 2'
  #   # [main] WARN org.asamk.signal.manager.helper.GroupHelper - Cannot create a V2 group as self does not have a versioned profile
  #   # [main] ERROR org.asamk.signal.manager.storage.SignalAccount - Error saving file: (was java.lang.NullPointerException) (through reference chain: org.asamk.signal.manager.storage.groups.JsonGroupStore["groups"]->org.asamk.signal.manager.storage.groups.GroupInfoV1["expectedV2Id"])
  #   # Creating new group "6oW4cvxphi6FIROn+JATZw==" …
  #   # ... Group created
  #   # but... group not visible.
  #   # Ahh: https://github.com/AsamK/signal-cli/issues/354
  # }

  # Add a person to group
  else if ((ARGV[1] == "gad") &&                \
           (NUM[ARGV[2]])     &&                \
           (NUM[ARGV[3]])) {
    err = system("signal-cli -u " MYNUM " updateGroup -g '" ARGV[2] "' -m " \
                 NUM[ARGV[3]])
    if (err)
      print "... Error. Could not add member"
  }
  
  # Send a message to <group> and write to logfile
  else if ((ARGV[1] == "gsn") &&                \
           (ARGC == 4) &&                       \
           (NUM[ARGV[2]])) {
    # (as long as the right # of arguments)
    
    err = system("signal-cli -u " MYNUM " send -g " NUM[ARGV[2]] \
                 " -m '" ARGV[3] "'")
    if (err) {
      print "sending failed!" > "/dev/stderr"
      exit 1
    }

    # TODO Check this format
    print "Group sent to: " NUM[ARGV[2]] "\nTimestamp: " DATE "\nBody: " \
      ARGV[3] "\n" >> LOG
  }

  # Edit config file
  else if (ARGV[1] == "cfg") {
    split(ENVIRON["AWKPATH"], e, ":")
    for (i in e) {
      gsub(/\/+$/,"",e[i])
      "test -e " e[i] "/scw_config.awk ; echo $?" | getline status
      if (!status)
        system("emacs " e[i] "/scw_config.awk &")
    }
  }
  
  # Show signal-cli commands
  else if (ARGV[1] == "cli")
    print                                                               \
      "signal-cli -u " MYNUM " addDevice --uri 'tsdevice:/?uuid=...'\n" \
      "signal-cli -u " MYNUM " listDevices\n"                           \
      "signal-cli -u " MYNUM " listIdentities\n"                        \
      "signal-cli -u " MYNUM " updateAccount\n"                         \
      "signal-cli -u " MYNUM " send +1234... -m 'message'\n"            \
      "signal-cli -u " MYNUM " send +1234... -a FILE.jpg\n"             \
      "signal-cli -u " MYNUM " receive\n"                               \
      "signal-cli -u " MYNUM " updateGroup -n 'New name'  NOT WORKING\n" \
      "signal-cli -u " MYNUM " updateGroup -g '1XAe...' -m +1234\n"     \
      "signal-cli -u " MYNUM " send -g '1XAe...' -m 'message'\n"        \
      "signal-cli -u " MYNUM " quitGroup -g '1XAe...'\n"                \
      "signal-cli -u " MYNUM " listGroups -d\n"                         \
      "signal-cli -u " MYNUM " trust +1234... -v '2345 4567 ...'\n"     \
      "signal-cli -u " MYNUM " updateProfile --name 'Joe' --avatar FILE.jpg\n" \
      "signal-cli -u " MYNUM " updateContact +1234... -n 'Jane'\n" \
      "signal-cli -u " MYNUM " sendContacts\n"
  
  # If no arguments, or other fail
  else {
    print USAGE
    exit 1
  }

  exit 0
}

# TODO add trust:
#  signal-cli -u +1xxxxxxxxxx trust -v "50467 94008 ..." +62yyyyyyyyyy

function format_line(msg, l1, col, ts,      lines, i,dash,ec,bc) {
  # arguments: message, message prefix, color, timestamp
  # (for colors: https://en.wikipedia.org/wiki/ANSI_escape_code )

  lines = int((length(msg)-1) / Width) + 1
  # create the dash, if needed
  ec = substr(msg,Width,1)
  bc = substr(msg,Width+1,1)
  dash = (ec && (ec!=" ") && bc && (bc!=" ")) ? "-" : ""

  # print the first format_line, preceded by date and name
  print "\x1b[38;5;8m" strftime("[%m-%d %a] ",ts) "\x1b[38;5;"  \
    col "m" l1 substr(msg,1,Width) dash
  
  for (i = 2; i <= lines; i++) {
    # print other lines
    ec = substr(msg,(i*Width),1)
    bc=substr(msg,(i*Width)+1,1)
    dash = (ec && (ec!=" ") && bc && (bc!=" ")) ? "-" : ""
    print sprintf("%*s", length(l1)+12, " ")                         \
      gensub(/^ */,"","G",substr(msg,((i-1)*Width)+1,Width)) dash
  }
  # print color reset:
  printf "\x1b[0;m"
}

function proc_nums(    i, n1, n2, nm, np) {
  gsub(/ +/,"",NUMS)
  gsub(/;$/,"",NUMS)
  split(NUMS, n1, ";")
  for (i in n1) {
    split(n1[i], n2, ":")
    nm[n2[1]]++
    np[n2[2]]++
    if((nm[n2[1]] > 1) || (np[n2[2]] > 1)) {
      print "Duplicate entry: " n1[i] > "/dev/stderr"
      exit 1
    }
    NUM[n2[1]] = n2[2]
    iNUM[n2[2]] = n2[1]
    if (n2[1] == MYNAME)
      MYNUM = n2[2]
  }
  if (!NUM[MYNAME]) {
    print "No MYNAME in config file" > "/dev/stderr"
    exit 1
  }
  # create SCLI
  SCLI = "/home/" ENVIRON["USER"] "/.local/share/signal-cli/data/" MYNUM ".d/"
}

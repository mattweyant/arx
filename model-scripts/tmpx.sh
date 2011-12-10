#!/bin/sh
set -e -u
unset rm_ dir
run=true
rm0=true ; rm1=true ; tag=tmpx ; tmp=/tmp # To be set by tool.
while [ $# > 0 ]
do
  tmp_set_by_option=false
  case "$1" in
    --no-rm)    rm_=false ;;
    --no-run)   run=false ;;
    --extract)  rm_=false ; run=false ; $tmp_set_by_option || tmp="" ;;
    --tmp)      tmp="$2"  ; shift     ; tmp_set_by_option=true ;;
    *)          echo 'Bad args.' >&2  ; exit 2 ;;
  esac
  shift
done
if [ "$tmp" != "" ]
then
  dir="$tmp"/"$tag".`date -u +%FT%TZ`.$$
  : ${rm_:=true}
  if $rm_
  then
    rm -rf "$dir"
    trap "case \$?/$rm0/$rm1 in
            0/true/*)      rm -rf \"\$dir\" ;;
            [1-9]*/*/true) rm -rf \"\$dir\" ;;
          esac" EXIT
    trap "exit 2" HUP INT QUIT BUS SEGV PIPE TERM
  fi
  mkdir -p "$dir"
  cd "$dir"
fi
go () {
  unpack_env > ./env
  unpack_run > ./run ; chmod ug+x ./run
  mkdir dat
  cd dat
  unpack_dat
  if $run
  then
    ( . ../env && ../run )
  fi
}
unpack_env () { : # NOOP
  # To be set by tool.
}
unpack_run () { : # NOOP
  # To be set by tool.
}
unpack_dat () { : # NOOP
  # To be set by tool.
}
go

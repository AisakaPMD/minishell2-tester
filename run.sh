#!/bin/bash

if [ -z "$MYSHELL" ]; then
    MYSHELL="$PWD/mysh"
fi
REFER="/bin/tcsh -f"
TRAPSIG=0

CAT=$(which cat)
GREP=$(which grep)
SED=$(which sed)
RM=$(which rm)
TR=$(which tr)
HEAD=$(which head)
TAIL=$(which tail)
WC=$(which wc)
CHMOD=$(which chmod)
EXPR=$(which expr)
MKDIR=$(which mkdir)
CP=$(which cp)

ESC="\x1B["
C_RESET=$ESC"0m"
C_BRED=$ESC'41m'
C_BGRN=$ESC"42m"
C_FRED=$ESC"31m"
C_FLRED=$ESC"1;31m"
C_FYEL=$ESC'33m'
C_FLYEL=$ESC'1;33m'
C_FGRN=$ESC'32m'
C_FLGRN=$ESC'1;32m'

PER=0
TOTAL=0
DEAD=0

NB_OK=0
NB_FAIL=0
NB_CRASH=0

chmod 777 mysh

echo -e '#!/bin/bash\nSIG=SEGV; if (( $# >= 1 )); then SIG=$1; fi; kill -${SIG} $$' >/tmp/segdoer
chmod 777 /tmp/segdoer
cp /tmp/segdoer /tmp/segdoersuid
chmod u+s /tmp/segdoersuid

for i in $(env | grep BASH_FUNC_ | cut -d= -f1); do
    f=$(echo $i | sed s/BASH_FUNC_//g | sed s/%%//g)
    unset -f $f
done

disp_test() {
    id=$1
    $CAT tests | $GREP -A1000 "\[$id\]" | $GREP -B1000 "^\[$id-END\]" | $GREP -v "^\[.*\]"
}

run_script() {
    SC="$1"
    echo "$SC" >/tmp/.tmp.$$
    . /tmp/.tmp.$$
    $RM -f /tmp/.tmp.$$
}

prepare_test() {
    local testfn="/tmp/.tester.$$"
    local runnerfn="/tmp/.runner.$$"
    local refoutfn="/tmp/.refer.$$"
    local shoutfn="/tmp/.shell.$$"

    WRAPPER="$runnerfn"

    echo "#!/bin/bash" >$runnerfn
    echo "$SETUP" >>$runnerfn
    echo "/bin/bash -c '"$testfn" | "$MYSHELL" ; echo Shell exit with code \$?' > "$shoutfn" 2>&1" >>$runnerfn
    echo "$CLEAN" >>$runnerfn
    echo "$SETUP" >>$runnerfn
    echo "$TCSHUPDATE" >>$runnerfn
    echo "/bin/bash -c '"$testfn" | "$REFER" ; echo Shell exit with code \$?' > "$refoutfn" 2>&1" >>$runnerfn
    echo "$CLEAN" >>$runnerfn

    echo "#!/bin/bash" >$testfn
    echo "$TESTS" | $TR "²" "\n" >>$testfn

    chmod 755 $testfn
    chmod 755 $runnerfn
}

load_test() {
    id=$1
    debug=$2
    SETUP=$(disp_test "$id" | $GREP "SETUP=" | $SED s/'SETUP='// | $SED s/'"'//g)
    CLEAN=$(disp_test "$id" | $GREP "CLEAN=" | $SED s/'CLEAN='// | $SED s/'"'//g)
    NAME=$(disp_test "$id" | $GREP "NAME=" | $SED s/'NAME='// | $SED s/'"'//g)
    TCSHUPDATE=$(disp_test "$id" | $GREP "TCSHUPDATE=" | $SED s/'TCSHUPDATE='// | $SED s/'"'//g)
    TESTS=$(disp_test "$id" | $GREP -v "SETUP=" | $GREP -v "CLEAN=" | $GREP -v "NAME=" | $GREP -v "TCSHUPDATE=" | $GREP -v "TESTS=" | $TR "\n" "²" | $SED s/"²$"//)
    TRACE='OK'
    $MKDIR -p "/tmp/test.$$" 2>/dev/null
    touch "/tmp/test.$$/trace.txt"
    prepare_test
    $WRAPPER
    nb=$($CAT /tmp/.refer.$$ | $GREP -v '^_=' | $GREP -v '^\[1\]' | $WC -l)
    i=1
    ok=1
    while [ $i -le $nb ]; do
        l=$($CAT /tmp/.refer.$$ | $GREP -v '^_=' | $GREP -v '^\[1\]' | $HEAD -$i | $TAIL -1)
        lescaped=$(sed 's/[^^]/[&]/g; s/\^/\\^/g' <<<"$l")
        a=$($CAT /tmp/.shell.$$ | $GREP -v '^_=' | $GREP -v '^\[1\]' | $GREP -- "$lescaped$" | $WC -l)
        atxt=$($CAT /tmp/.shell.$$ | $GREP -v '^_=' | $GREP -v '^\[1\]' | $HEAD -$i | $TAIL -1)
        if [ $a -eq 0 ]; then
            if [ $ok -eq 1 ]; then
                TRACE="KO: Output differs: Line $i, tcsh said:\n< $l\n\nBut this line was not found on 42sh. For reference, line $i of 42sh is:\n> $atxt"
            fi
            ok=0
        fi
        i=$($EXPR $i + 1)
    done

    if [ $ok -eq 1 ]; then
        ((NB_OK++))
        if [ $debug -ge 1 ]; then
            printf '['"$C_FLGRN"'OK'"${C_RESET}] %s (%s)\n" "$id" "$NAME"
            # echo "Test $id ($NAME) : OK"
            if [ $debug -eq 2 ]; then
                echo "Output $MYSHELL :"
                $CAT -e /tmp/.shell.$$
                echo ""
                echo "Output $REFER :"
                $CAT -e /tmp/.refer.$$
                echo ""
            fi
        else
            echo "OK"
        fi
    else
        ((NB_FAIL++))
        if [ $debug -ge 1 ]; then
            printf '['"$C_FLRED"'KO'"${C_RESET}] %s (%s)\n" "$id" "$NAME"
            # echo "Test $id ($NAME) : KO - Check output in /tmp/test.$$/$id/"
            $MKDIR -p /tmp/test.$$/$id 2>/dev/null
            $CP /tmp/.shell.$$ /tmp/test.$$/$id/mysh.out
            $CP /tmp/.refer.$$ /tmp/test.$$/$id/tcsh.out
        else
            echo "KO"
        fi
        echo -e '\n\n\n===== '"$id"' =====\n'"$NAME\n$TRACE\n\n===== --- =====\n" >>"/tmp/test.$$/trace.txt"
    fi
}

#if [ $TRAPSIG -eq 1 ]; then
#for sig in $(trap -l); do
#    echo "Attention [$sig]"
#    echo "$sig" | grep "^SIG" >/dev/null 2>&1

#if [ $? -eq 0 ]; then
#    trap "echo Received signal $sig !" $sig
#    ((NB_CRASH++))
#fi
#done
#fi

if [ ! -f tests ]; then
    echo "No tests file. Please read README.ME" >&2
    exit 1
fi

if [ ! -f $MYSHELL ]; then
    echo "$MYSHELL not found" >&2
    exit 1
fi

if [ $# -eq 2 ]; then
    echo "Debug mode" >&2
    echo "Shell : $MYSHELL" >&2
    echo "Reference : $REFER" >&2
    echo ""
fi

if [ $# -eq 0 ]; then
    for lst in $(cat tests | grep "^\[.*\]$" | grep -vi end | sed s/'\['// | sed s/'\]'//); do
        path_backup=$PATH
        load_test $lst 1
        export PATH=$path_backup
    done
else
    if [ $# -eq 1 ]; then
        load_test $1 0
    else
        if [ "X$1" = "X-d" ]; then
            load_test $2 2
        else
            load_test $1 2
        fi
    fi
fi

NB_TOTAL=$((NB_OK + NB_FAIL + NB_CRASH))
RES=$(echo "scale=2; $NB_OK * 100 / $NB_TOTAL" | bc)
RES_FULL=$((NB_OK * 100 / NB_TOTAL))
RES_TENTH=$((NB_OK * 20 / NB_TOTAL))
RES_TENTH_ITERATOR=0

if ((NB_OK < NB_TOTAL)); then
    echo ''
fi
echo -e '== Tests Summary =='
echo -e 'OK: '$NB_OK
echo -e 'Failed: '$NB_FAIL
echo -e 'Crashed: '$NB_CRASH
echo -e ''
echo -e "Trace can be found at /tmp/test.$$/trace.txt"
echo -e ''

if ((NB_OK < NB_TOTAL)); then
    echo '' >>"/tmp/test.$$/trace.txt"
fi
echo -e '== Tests Summary ==' >>"/tmp/test.$$/trace.txt"
echo -e 'OK: '$NB_OK >>"/tmp/test.$$/trace.txt"
echo -e 'Failed: '$NB_FAIL >>"/tmp/test.$$/trace.txt"
echo -e 'Crashed: '$NB_CRASH >>"/tmp/test.$$/trace.txt"
echo -e '' >>"/tmp/test.$$/trace.txt"
echo -e "Trace can be found at /tmp/test.$$/trace.txt" >>"/tmp/test.$$/trace.txt"
echo -e '' >>"/tmp/test.$$/trace.txt"

PERCENTAGE_COLOUR=$C_BRED
if ((RES_FULL > 0)); then
    PERCENTAGE_COLOUR=$C_FLRED
fi
if ((RES_FULL >= 20)); then
    PERCENTAGE_COLOUR=$C_FRED
fi
if ((RES_FULL >= 40)); then
    PERCENTAGE_COLOUR=$C_FYEL
fi
if ((RES_FULL >= 60)); then
    PERCENTAGE_COLOUR=$C_FLYEL
fi
if ((RES_FULL >= 80)); then
    PERCENTAGE_COLOUR=$C_FLGRN
fi
if ((RES_FULL == 100)); then
    PERCENTAGE_COLOUR=$C_BGRN
fi

echo -e 'Percentage: '${PERCENTAGE_COLOUR}${RES}'%'${C_RESET}
printf '['
while ((RES_TENTH_ITERATOR < 20)); do
    if ((RES_TENTH_ITERATOR < RES_TENTH)); then
        printf '='
    else
        printf ' '
    fi
    ((RES_TENTH_ITERATOR++))
done
printf ']\n'

rm /tmp/segdoer

ARCHIVE_NAME="latest.tar.gz"
echo ":: Creating archive"

WD=$(/bin/pwd)

rm -f "$ARCHIVE_NAME"
(
    cd "/tmp/test.$$"
    tar -czf "$WD/$ARCHIVE_NAME" *
)

echo ":: Results saved in $WD/$ARCHIVE_NAME"

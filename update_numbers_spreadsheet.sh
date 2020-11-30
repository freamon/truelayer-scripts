#!/usr/bin/env bash

# For use on MacOS
# Calls tlob.sh with 'balance' and 'transactions' commands and
# creates an AppleScript to update Numbers spreadsheet app
#
# Andrew Slater

# this script's directory
DIR="${BASH_SOURCE%/*}"

## --------- transactions --------- ##

printf -v today '%(%F)T' -1
IFS='-' read year month day < <(echo $today)

pay_year=$year
pay_day=21
if [ $day -lt 21 ]
then
    if [ $month -gt 1 ]
    then
        pay_month=$(( month-1 ))
        if [ $pay_month -lt 10 ]
        then
            pay_month="0$pay_month"
        fi
    else
        pay_month=12
        pay_year=$(( year-1 ))
    fi
else
    pay_month=$month
fi

# last time I was paid
pay_date="$pay_year-$pay_month-$pay_day"

# get transactions from pay date to today
$DIR/tlob.sh live transactions 123456789abcdef123456789abcdef22 $pay_date > /tmp/transactions.json
status=$(cat /tmp/transactions.json | jq -r '.status')

if [ "$status" == "Succeeded" ]
then
    jq '.results[].description' /tmp/transactions.json > /tmp/descriptions.txt
    readarray descriptions < /tmp/descriptions.txt
    jq '.results[].amount' /tmp/transactions.json > /tmp/amounts.txt
    readarray amounts < /tmp/amounts.txt
    rowcount=$(( $(jq '.results | length' /tmp/transactions.json) + 1 ))
else
    echo "Error retrieving account transactions"
    exit
fi

# start creating an AppleScript
echo -n "#!/usr/bin/osascript

tell application \"Numbers\"
    activate
    open \"${HOME}/Documents/Home/Spending.numbers\"
    tell table 1 of sheet \"Local\" of document 1
        set row count to $rowcount" > /tmp/update_numbers.scpt

i=2; j=0
while [ $i -le $rowcount ]
    do echo -n "
        set the value of cell $i of column \"B\" to ${descriptions[$j]}
        set the value of cell $i of column \"C\" to ${amounts[$j]}" >> /tmp/update_numbers.scpt
    i=$(( i+1 ))
    j=$(( j+1 ))
done


## --------- balance --------- ## 
json=$($DIR/tlob.sh live balance 185e98dbcbb8d3ac65a3d49350ded5ea)
status=$(echo $json | jq -r '.status')

if [ "$status" == "Succeeded" ]
then
    balance=$(echo $json | jq -r '.results[].available')
else
    echo "Error retrieving account balance"
    exit
fi

# finish creating an AppleScript, then run it
echo -n "
    end tell
    tell table 1 of sheet \"Pots\" of document 1
        set the value of cell 25 of column \"D\" to $balance
        set the format of cell 25 of column \"D\" to currency
    end tell
end tell" >> /tmp/update_numbers.scpt

chmod +x /tmp/update_numbers.scpt
/tmp/update_numbers.scpt

exit

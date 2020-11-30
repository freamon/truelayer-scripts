#!/usr/bin/env bash

# Script for use with API at truelayer.com (open banking provider)
#
# Andrew Slater

# location to store TrueLayer tokens
tokens_file="${HOME}/.tlob_tokens.json"

# this script's directory
DIR="${BASH_SOURCE%/*}"

# how-to usage message, called if input is invalid 
usage_message () {
    echo "USAGE: tlob.sh ENVIRONMENT COMMAND [PARAMETERS]"
    echo "Valid environments:"
    echo "  sandbox"
    echo "  live"
    echo "Valid commands:"
    echo "  setup"
    echo "  info"
    echo "  accounts"
    echo "  balance             (requires account_id parameter)"
    echo "  transactions        (requires account_id parameter, 'from' and 'to' dates are optional)"
    echo "  pending             (requires account_id parameter)"
    echo "  direct_debits       (requires account_id parameter)"
    echo "  standing_orders     (requires account_id parameter)"
    echo "  cards"
    echo "  card_balance        (requires account_id parameter)"
    echo "  card_transactions   (requires account_id parameter, 'from' and 'to' dates are optional)"
    echo "  card_pending        (requires account_id parameter)"
    echo "Valid parameters:"
    echo "  code from truelayer.com authentication link (for use with 'setup' command)" 
    echo "  account_id (for use with 'accounts', 'balance', 'transactions', etc commands"
    echo "  from_date, to_date (optionally used with 'transactions' command)"
    echo ""
    echo "Examples:"
    echo "./tlob.sh sandbox setup"
    echo "./tlob.sh sandbox info"
    echo "./tlob.sh sandbox accounts"
    echo "./tlob.sh sandbox accounts 8de2de9eab01b935b21abcbed11adf26"
    echo "./tlob.sh sandbox balance 8de2de9eab01b935b21abcbed11adf26"
    echo "./tlob.sh sandbox transactions 8de2de9eab01b935b21abcbed11adf26"
    echo "./tlob.sh sandbox transactions 8de2de9eab01b935b21abcbed11adf26 2020-10-21"
    echo "./tlob.sh sandbox transactions 8de2de9eab01b935b21abcbed11adf26 2020-10-21 2020-11-30"
    echo "./tlob.sh sandbox pending 8de2de9eab01b935b21abcbed11adf26"
    echo "./tlob.sh sandbox direct_debits 8de2de9eab01b935b21abcbed11adf26"
    
    exit
}

# read local tokens file, and refresh access token if required
read_tokens () {
    if [ ! -f "$tokens_file" ]
    then
        echo "Missing tokens.  Run setup.sh with code provided by TrueLayer"
        exit
    fi

    tokens=$(cat "$tokens_file" | jq -r '.access, .expiry, .scope')
    read access expiry scope < <(echo $tokens)

    if [ $EPOCHSECONDS -ge $expiry ]
    then
        # Expired token
        if [[ "$scope" =~ 'offline_access' ]]
        then
            refresh=$(cat "$tokens_file" | jq -r '.refresh')

            response=$(curl --silent --location --request POST \
                    "https://auth.$tl_url/connect/token" \
                    --data-urlencode "grant_type=refresh_token" \
                    --data-urlencode "client_id=$client_id" \
                    --data-urlencode "client_secret=$client_secret" \
                    --data-urlencode "refresh_token=$refresh" | jq '.')

            if [[ "$response" =~ 'error' ]] 
            then
                echo "$response"
                exit
            else
                expiry=$(echo "$response" | jq ".expires_in+$EPOCHSECONDS")
                echo "$response" | jq ". | {access: .access_token, \
                                            expiry: $expiry, \
                                            refresh: .refresh_token, \
                                            scope: .scope}" \
                                            > "$tokens_file"
                access=$(cat "$tokens_file" | jq -r '.access')
            fi
        else
            echo "Error: token expired. Not authorised to refresh"
            echo "Run 'tlob.sh setup' again, with new code from TrueLayer"
            exit
        fi
    fi
}

# ensure action was authorised when authentication link was constructed
check_permissions () {
    if [ "$#" -eq 1 ]
    then
        if [[ ! "$scope" =~ "$1" ]]
        then
            echo "Error: not authorised. $1 not included in scope"
            exit  
        fi
    elif [ "$#" -eq 2 ]
    then
        if [[ ! "$scope" =~ "$1" || ! "$scope" =~ "$2" ]]
        then
            echo "Error: not authorised. $1 and $2 not included in scope"
            exit  
        fi
    fi
}

if [ "$#" -lt 2 ]
then
    usage_message
fi

# sandbox and live environments use different URLs
if [ $1 == "sandbox" ]
then
    tl_url="truelayer-sandbox.com"
elif [ $1 == "live" ]
then
    tl_url="truelayer.com"
else
    usage_message
fi

# read data from sandbox.cfg or live.cfg
client_info=$(cat $DIR/$1.cfg | jq -r '.client_id, .client_secret')
if [ "$client_info" == "" ]
then
    echo "ERROR: Populate $1.cfg with data from truelayer.com account"
    exit
fi
    
# split info into $client_id and $client_secret
read client_id client_secret < <(echo $client_info)
if [[ "$client_id" == "" ||
      "$client_secret" == "" ]]
then
    echo "ERROR: Populate $1.cfg with data from truelayer.com account"
    exit
fi

# COMMAND: 'setup'
# populate local $tokens_file with data from truelayer.com
if [ "$2" == "setup" ]
then
    if [ "$#" -eq 3 ]
    then
        code=$3
    else
        read -p "Construct an authentication link at truelayer.com and paste code provided here: " code
    fi

    response=$(curl --silent --location --request POST \
                "https://auth.$tl_url/connect/token" \
                --data-urlencode "grant_type=authorization_code" \
                --data-urlencode "client_id=$client_id" \
                --data-urlencode "client_secret=$client_secret" \
                --data-urlencode "redirect_uri=https://console.truelayer.com/redirect-page" \
                --data-urlencode "code=$code" | jq '.')

    if [[ "$response" =~ 'error' ]]
    then
        echo "$response"
        echo "(Error most likely caused by time-expired code)"
        exit
    else
        expiry=$(echo "$response" | jq ".expires_in+$EPOCHSECONDS")
        scope=$(echo "$response" | jq '.scope')
        
        if [[ "$scope" =~ 'offline_access' ]]
        then
            echo "$response" | jq ". | {access: .access_token, \
                                        expiry: $expiry, \
                                        refresh: .refresh_token, \
                                        scope: .scope}" \
                > "$tokens_file"
        else
            echo "$response" | jq ". | {access: .access_token, \
                                        expiry: $expiry, \
                                        scope: .scope}" \
                > "$tokens_file"
        fi
    fi
fi

# COMMAND: 'info'
# print bank user info
if [ "$2" == "info" ]
then
    read_tokens
    check_permissions $2

    curl --silent --header "Authorization: Bearer $access" \
        "https://api.$tl_url/data/v1/$2" | jq '.'
fi

# COMMAND: 'accounts' or 'cards'
# print data for all cards/accounts or just for account_id if parameter used
if [[ "$2" == "accounts" || "$2" == "cards" ]]
then
    read_tokens
    check_permissions $2

    if [ "$#" -eq 3 ]
    then
        account_id=$3
        curl --silent --header "Authorization: Bearer $access" \
            "https://api.$tl_url/data/v1/$2/$account_id" | jq '.'
    else
        curl --silent --header "Authorization: Bearer $access" \
            "https://api.$tl_url/data/v1/$2" | jq '.'
    fi
fi

# COMMAND: 'balance'
# print balance for given account_id
if [ "$2" == "balance" ]
then
    read_tokens
    check_permissions $2

    if [ "$#" -eq 3 ]
    then
        account_id=$3
        curl --silent --header "Authorization: Bearer $access" \
            "https://api.$tl_url/data/v1/accounts/$account_id/$2" | jq '.'
    else
        usage_message
    fi
fi

# COMMAND: 'transactions'
# print transactions for given account_id
if [ "$2" == "transactions" ]
then
    read_tokens
    check_permissions $2

    if [ "$#" -lt 3 ]
    then
        usage_message
    fi

    if [ "$#" -eq 3 ]
    then
        account_id=$3
        curl --silent --header "Authorization: Bearer $access" \
            "https://api.$tl_url/data/v1/accounts/$account_id/$2" | jq '.'
    fi

    if [ "$#" -eq 4 ]
    then
        account_id=$3
        from_date=$4
        printf -v today '%(%F)T' -1
        curl --silent --header "Authorization: Bearer $access" \
            "https://api.$tl_url/data/v1/accounts/$account_id/$2?from=${from_date}&to=${today}" | jq '.'
    fi

    if [ "$#" -eq 5 ]
    then
        account_id=$3
        from_date=$4
        to_date=$5
        curl --silent --header "Authorization: Bearer $access" \
            "https://api.$tl_url/data/v1/accounts/$account_id/$2?from=${from_date}&to=${to_date}" | jq '.'
    fi
fi

# COMMAND: 'pending'
# print pending transactions for given account_id
if [ "$2" == "pending" ]
then
    read_tokens
    check_permissions "transactions"

    if [ "$#" -eq 3 ]
    then
        account_id=$3
        curl --silent --header "Authorization: Bearer $access" \
            "https://api.$tl_url/data/v1/accounts/$account_id/transactions/$2" | jq '.'
    else
        usage_message
    fi
fi

# COMMAND: 'direct_debits' or 'standing_orders'
# print direct debits or standing orders for given account_id
if [[ "$2" == "direct_debits" || "$2" == "standing_orders" ]]
then
    read_tokens
    check_permissions $2 "accounts"

    if [ "$#" -eq 3 ]
    then
        account_id=$3
        curl --silent --header "Authorization: Bearer $access" \
            "https://api.$tl_url/data/v1/accounts/$account_id/$2" | jq '.'
    else
        usage_message
    fi
fi

# COMMAND: 'card_balance'
# print card balance for given account_id
if [ "$2" == "card_balance" ]
then
    read_tokens
    check_permissions "cards" "balance"

    if [ "$#" -eq 3 ]
    then
        account_id=$3
        curl --silent --header "Authorization: Bearer $access" \
            "https://api.$tl_url/data/v1/cards/$account_id/balance" | jq '.'
    else
        usage_message
    fi
fi

# COMMAND: 'card_transactions'
# print card transactions for given account_id
if [ "$2" == "card_transactions" ]
then
    read_tokens
    check_permissions "cards" "transactions"

    if [ "$#" -lt 3 ]
    then
        usage_message
    fi

    if [ "$#" -eq 3 ]
    then
        account_id=$3
        curl --silent --header "Authorization: Bearer $access" \
            "https://api.$tl_url/data/v1/cards/$account_id/transactions" | jq '.'
    fi

    if [ "$#" -eq 4 ]
    then
        account_id=$3
        from_date=$4
        printf -v today '%(%F)T' -1
        curl --silent --header "Authorization: Bearer $access" \
            "https://api.$tl_url/data/v1/cards/$account_id/transactions?from=${from_date}&to=${today}" | jq '.'
    fi

    if [ "$#" -eq 5 ]
    then
        account_id=$3
        from_date=$4
        to_date=$5
        curl --silent --header "Authorization: Bearer $access" \
            "https://api.$tl_url/data/v1/cards/$account_id/transactions?from=${from_date}&to=${to_date}" | jq '.'
    fi
fi

# COMMAND: 'card_pending'
# print card pending transactions for given account_id
if [ "$2" == "card_pending" ]
then
    read_tokens
    check_permissions "cards" "transactions"

    if [ "$#" -eq 3 ]
    then
        account_id=$3
        curl --silent --header "Authorization: Bearer $access" \
            "https://api.$tl_url/data/v1/cards/$account_id/transactions/pending" | jq '.'
    else
        usage_message
    fi
fi

exit

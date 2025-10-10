#!/bin/bash

# Ensure at least three arguments are provided
if [[ $# -lt 3 ]]; then
    echo "Usage: ./deploy.sh [prompt|account|pk] [network] [script] [--test (optional)]"
    exit 1
fi

# Assign arguments
AUTH_METHOD=$1
NETWORK=$2
SCRIPT_NAME=$3
TEST_MODE=false

# Check for optional "--test" flag
for arg in "$@"; do
    if [[ "$arg" == "--test" ]]; then
        TEST_MODE=true
    fi
done

# Load environment variables robustly (handles spaces around =, quotes, and comments)
set -a
while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    # Trim leading/trailing whitespace
    line="${raw_line#${raw_line%%[!$'\t\r\n ']*}}"
    line="${line%${line##*[!$'\t\r\n ']} }"

    # Skip empty or commented lines
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

    # Remove optional 'export' prefix
    if [[ "$line" =~ ^[[:space:]]*export[[:space:]]+(.+)$ ]]; then
        line="${BASH_REMATCH[1]}"
    fi

    # Parse KEY=VALUE with optional spaces around '='
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        # Trim surrounding whitespace in value
        value="${value#${value%%[!$'\t\r\n ']*}}"
        value="${value%${value##*[!$'\t\r\n ']} }"

        # If value is unquoted, strip trailing inline comments
        if [[ "$value" != \"* && "$value" != \'* ]]; then
            value="${value%%#*}"
            value="${value%${value##*[!$'\t\r\n ']} }"
        fi

        # Remove surrounding matching quotes if present
        if [[ ( "$value" == \"*\" && "$value" == *\" ) || ( "$value" == \'*\' && "$value" == *\' ) ]]; then
            value="${value:1:-1}"
        fi

        export "$key=$value"
    fi
done < .env
set +a

# Ensure RPC URL is set
case "$NETWORK" in
    "base")
        RPC_URL="$BASE_RPC_URL"
        ;;
    "sepolia")
        RPC_URL="$ETHEREUM_SEPOLIA_RPC_URL"
        ;;
    "base_sepolia")
        RPC_URL="$BASE_SEPOLIA_RPC_URL"
        ;;
    "ethereum")
        RPC_URL="$ETHEREUM_RPC_URL"
        ;;
    *)
        echo "Unsupported network: $NETWORK"
        exit 1
        ;;
esac

# Ensure RPC URL is not empty
if [[ -z "$RPC_URL" ]]; then
    echo "Error: RPC URL for network '$NETWORK' is not set in .env"
    exit 1
fi

# Base command
FORGE_CMD="forge script ./script/${SCRIPT_NAME}.s.sol \
    --rpc-url \"$RPC_URL\" \
    -g 200 \
    --force \
    --slow"

# Only add --broadcast and --verify if NOT in test mode
if [[ "$TEST_MODE" == false ]]; then
    FORGE_CMD="$FORGE_CMD --broadcast \
        --verify \
        --etherscan-api-key \"$ETHERSCAN_API_KEY\""
else
    echo "Running in test mode (no broadcast, no verify)."
fi

# Append authentication method
if [[ "$AUTH_METHOD" == "prompt" ]]; then
    FORGE_CMD="$FORGE_CMD --interactives 1"
elif [[ "$AUTH_METHOD" == "account" ]]; then
    FORGE_CMD="$FORGE_CMD --account \"$FORGE_ACCOUNT\""
elif [[ "$AUTH_METHOD" == "pk" ]]; then
    FORGE_CMD="$FORGE_CMD --private-key \"$FORGE_KEY\""
else
    echo "Unsupported authentication method: $AUTH_METHOD"
    exit 1
fi

# Execute command
echo "Executing: $FORGE_CMD"
eval $FORGE_CMD
#!/bin/bash

# Ensure at least three arguments are provided
if [[ $# -lt 3 ]]; then
    echo "Usage: ./deploy.sh [pk|account] [network] [script] [--test (optional)]"
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

# Load environment variables safely (handles quotes, spaces, and comments)
set -a
while IFS='=' read -r key value; do
    # Ignore commented lines and empty lines
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue

    # Remove surrounding quotes if they exist
    value="${value%\"}"
    value="${value#\"}"

    # Export the cleaned variable
    export "$key=$value"
done < .env
set +a

# Ensure RPC URL is set
case "$NETWORK" in
    "base")
        RPC_URL="$BASE_RPC_URL"
        ;;
    "base_sepolia")
        RPC_URL="$BASE_SEPOLIA_RPC_URL"
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
        --verifier-url https://api.basescan.org/api \
        --etherscan-api-key \"$BASESCAN_API_KEY\""
else
    echo "Running in test mode (no broadcast, no verify)."
fi

# Append authentication method
if [[ "$AUTH_METHOD" == "pk" ]]; then
    FORGE_CMD="$FORGE_CMD --interactives 1"
else
    FORGE_CMD="$FORGE_CMD --account \"$FORGE_ACCOUNT\""
fi

# Execute command
echo "Executing: $FORGE_CMD"
eval $FORGE_CMD

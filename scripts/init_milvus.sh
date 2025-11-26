#!/usr/bin/env bash
# Nova Milvus Vector Database Initialization
# Creates collections and indices for semantic search
set -euo pipefail

MILVUS_HOST=${MILVUS_HOST:-localhost}
MILVUS_PORT=${MILVUS_PORT:-19530}
MILVUS_URL="http://${MILVUS_HOST}:${MILVUS_PORT}"

# Collection configurations
POST_COLLECTION="post_embeddings"
USER_COLLECTION="user_embeddings"
EMBEDDING_DIM=${EMBEDDING_DIM:-768}

echo "=== Nova Milvus Initialization ==="
echo "Milvus URL: ${MILVUS_URL}"
echo "Embedding dimension: ${EMBEDDING_DIM}"
echo ""

# Wait for Milvus to be ready
echo "1. Checking Milvus connectivity..."
for i in {1..30}; do
    if curl -sf "${MILVUS_URL}/healthz" > /dev/null 2>&1; then
        echo "   ✓ Milvus is healthy"
        break
    fi
    echo "   Waiting for Milvus... (${i}/30)"
    sleep 2
done

if ! curl -sf "${MILVUS_URL}/healthz" > /dev/null 2>&1; then
    echo "   ✗ ERROR: Milvus not responding at ${MILVUS_URL}"
    exit 1
fi

# Function to create collection via REST API
create_collection() {
    local COLLECTION_NAME=$1
    local SCHEMA=$2

    echo ""
    echo "Creating collection: ${COLLECTION_NAME}"

    # Check if collection exists
    EXISTS=$(curl -sf "${MILVUS_URL}/v1/vector/collections/${COLLECTION_NAME}" 2>/dev/null | grep -c "collection_name" || echo "0")

    if [ "$EXISTS" -gt 0 ]; then
        echo "   Collection ${COLLECTION_NAME} already exists"
        return 0
    fi

    # Create collection
    RESPONSE=$(curl -sf -X POST "${MILVUS_URL}/v1/vector/collections/create" \
        -H "Content-Type: application/json" \
        -d "${SCHEMA}" 2>&1) || {
        echo "   ✗ Failed to create collection: ${RESPONSE}"
        return 1
    }

    echo "   ✓ Collection ${COLLECTION_NAME} created"
}

# Function to create index
create_index() {
    local COLLECTION_NAME=$1
    local FIELD_NAME=$2
    local INDEX_TYPE=${3:-HNSW}

    echo "   Creating index on ${COLLECTION_NAME}.${FIELD_NAME} (${INDEX_TYPE})"

    local INDEX_PARAMS
    if [ "$INDEX_TYPE" = "HNSW" ]; then
        INDEX_PARAMS='{"M": 16, "efConstruction": 256}'
    else
        INDEX_PARAMS='{"nlist": 1024}'
    fi

    curl -sf -X POST "${MILVUS_URL}/v1/vector/indexes/create" \
        -H "Content-Type: application/json" \
        -d "{
            \"collectionName\": \"${COLLECTION_NAME}\",
            \"fieldName\": \"${FIELD_NAME}\",
            \"indexName\": \"${FIELD_NAME}_idx\",
            \"metricType\": \"COSINE\",
            \"indexType\": \"${INDEX_TYPE}\",
            \"params\": ${INDEX_PARAMS}
        }" > /dev/null 2>&1 || true

    echo "   ✓ Index created"
}

# 2. Create post_embeddings collection
echo ""
echo "2. Creating post_embeddings collection..."

POST_SCHEMA='{
    "collectionName": "'"${POST_COLLECTION}"'",
    "dimension": '"${EMBEDDING_DIM}"',
    "metricType": "COSINE",
    "description": "Post content embeddings for semantic search",
    "fields": [
        {
            "fieldName": "post_id",
            "dataType": "VarChar",
            "isPrimary": true,
            "maxLength": 36
        },
        {
            "fieldName": "embedding",
            "dataType": "FloatVector",
            "dimension": '"${EMBEDDING_DIM}"'
        },
        {
            "fieldName": "author_id",
            "dataType": "VarChar",
            "maxLength": 36
        },
        {
            "fieldName": "created_at",
            "dataType": "Int64"
        },
        {
            "fieldName": "engagement_score",
            "dataType": "Float"
        }
    ]
}'

create_collection "${POST_COLLECTION}" "${POST_SCHEMA}"
create_index "${POST_COLLECTION}" "embedding" "HNSW"

# 3. Create user_embeddings collection (for recommendation)
echo ""
echo "3. Creating user_embeddings collection..."

USER_SCHEMA='{
    "collectionName": "'"${USER_COLLECTION}"'",
    "dimension": '"${EMBEDDING_DIM}"',
    "metricType": "COSINE",
    "description": "User preference embeddings for recommendation",
    "fields": [
        {
            "fieldName": "user_id",
            "dataType": "VarChar",
            "isPrimary": true,
            "maxLength": 36
        },
        {
            "fieldName": "embedding",
            "dataType": "FloatVector",
            "dimension": '"${EMBEDDING_DIM}"'
        },
        {
            "fieldName": "updated_at",
            "dataType": "Int64"
        }
    ]
}'

create_collection "${USER_COLLECTION}" "${USER_SCHEMA}"
create_index "${USER_COLLECTION}" "embedding" "HNSW"

# 4. Load collections into memory
echo ""
echo "4. Loading collections into memory..."

curl -sf -X POST "${MILVUS_URL}/v1/vector/collections/${POST_COLLECTION}/load" > /dev/null 2>&1 || true
curl -sf -X POST "${MILVUS_URL}/v1/vector/collections/${USER_COLLECTION}/load" > /dev/null 2>&1 || true

echo "   ✓ Collections loaded"

# 5. Verify collections
echo ""
echo "5. Verifying collections..."

for COLLECTION in "${POST_COLLECTION}" "${USER_COLLECTION}"; do
    INFO=$(curl -sf "${MILVUS_URL}/v1/vector/collections/${COLLECTION}" 2>/dev/null || echo "{}")
    if echo "${INFO}" | grep -q "collection_name"; then
        echo "   ✓ ${COLLECTION}: OK"
    else
        echo "   ✗ ${COLLECTION}: NOT FOUND"
    fi
done

echo ""
echo "=== Milvus Initialization Complete ==="
echo ""
echo "Collections created:"
echo "  - ${POST_COLLECTION} (dim=${EMBEDDING_DIM})"
echo "  - ${USER_COLLECTION} (dim=${EMBEDDING_DIM})"
echo ""
echo "Next steps:"
echo "  1. Ensure MILVUS_URL is set in services"
echo "  2. Run embedding pipeline to populate vectors"
echo "  3. Monitor with: curl ${MILVUS_URL}/v1/vector/collections"

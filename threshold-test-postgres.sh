#!/bin/bash

echo "🐘 POSTGRESQL THRESHOLD TEST: Finding optimal sustained load"
echo "==========================================================="

# Configuration for PostgreSQL threshold testing
TARGET="localhost:2802"
EVENTS_PER_SECOND=150  # Start higher than Redis
TEST_DURATION=60
TOTAL_EVENTS=$((EVENTS_PER_SECOND * TEST_DURATION))
BATCH_SIZE=15
BATCHES_PER_SECOND=$((EVENTS_PER_SECOND / BATCH_SIZE))
SLEEP_BETWEEN_BATCHES=$(echo "scale=3; 1.0 / $BATCHES_PER_SECOND" | bc)

echo "Configuration:"
echo "- Target rate: $EVENTS_PER_SECOND events/sec"
echo "- Test duration: ${TEST_DURATION}s"
echo "- Total events: $TOTAL_EVENTS"
echo "- Batch size: $BATCH_SIZE events"
echo "- Batches per second: $BATCHES_PER_SECOND"
echo "- Sleep between batches: ${SLEEP_BETWEEN_BATCHES}s"
echo ""

# Start PostgreSQL backend
echo "🔄 Starting PostgreSQL backend..."
FALCOSIDEKICK_UI_DATABASE_BACKEND=postgres \
FALCOSIDEKICK_UI_POSTGRES_HOST=localhost \
FALCOSIDEKICK_UI_POSTGRES_PORT=5432 \
FALCOSIDEKICK_UI_POSTGRES_USER=falco \
FALCOSIDEKICK_UI_POSTGRES_PASSWORD=falco \
FALCOSIDEKICK_UI_POSTGRES_DB=falco \
/tmp/falcosidekick-ui -x true -l info -d > /tmp/postgres-threshold.log 2>&1 &
BACKEND_PID=$!

sleep 8  # PostgreSQL needs more startup time

# Verify backend is running
if ! curl -s http://$TARGET/api/v1/healthz | grep -q "ok"; then
    echo "❌ Backend failed to start"
    kill $BACKEND_PID 2>/dev/null
    exit 1
fi

echo "✅ PostgreSQL backend started (PID: $BACKEND_PID)"

# Function to send a controlled batch with complex data
send_controlled_batch() {
    local batch_id=$1
    local success_count=0
    
    for i in $(seq 1 $BATCH_SIZE); do
        local uuid=$(cat /proc/sys/kernel/random/uuid)
        local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local priority_array=("Emergency" "Alert" "Critical" "Error" "Warning" "Notice" "Info" "Debug")
        local source_array=("k8s" "docker" "systemd" "nginx" "mysql" "postgres")
        local priority=${priority_array[$((RANDOM % 8))]}
        local source=${source_array[$((RANDOM % 6))]}
        
        # Complex event data to test PostgreSQL's capabilities
        local node_id=$((RANDOM % 20))
        local container_id="container-$((RANDOM % 1000))"
        
        if curl -s -X POST http://$TARGET/api/v1/ \
            -H "Content-Type: application/json" \
            -d "{
                \"event\": {
                    \"uuid\": \"$uuid\",
                    \"output\": \"PostgreSQL threshold test batch $batch_id event $i - sustained load at $EVENTS_PER_SECOND events/sec with complex data structures, long text fields, and nested JSON to test database performance under realistic workloads\",
                    \"priority\": \"$priority\",
                    \"rule\": \"PostgreSQL Threshold Test Rule for $source\",
                    \"time\": \"$timestamp\",
                    \"source\": \"$source\",
                    \"output_fields\": {
                        \"batch_id\": \"$batch_id\",
                        \"event_number\": \"$i\",
                        \"test_type\": \"threshold\",
                        \"node_id\": \"node-$node_id\",
                        \"container_id\": \"$container_id\",
                        \"process_name\": \"threshold-test-process\",
                        \"file_path\": \"/var/log/threshold-test-$batch_id-$i.log\",
                        \"user_name\": \"threshold-user-$((i % 10))\",
                        \"command_line\": \"./threshold-test --batch=$batch_id --event=$i --rate=$EVENTS_PER_SECOND\",
                        \"network_connection\": \"tcp://192.168.100.$((i % 255)):$((9000 + (i % 1000)))\",
                        \"metadata\": {
                            \"test_run\": true,
                            \"load_test\": \"postgresql-threshold\",
                            \"performance_target\": \"$EVENTS_PER_SECOND eps\",
                            \"complex_data\": {
                                \"nested_field\": \"value_$i\",
                                \"array_data\": [\"item1\", \"item2\", \"item3\"],
                                \"number_field\": $((i * batch_id))
                            }
                        }
                    },
                    \"hostname\": \"postgres-threshold-host-$((batch_id % 10))\",
                    \"tags\": [\"threshold\", \"postgresql\", \"sustained-load\", \"batch-$batch_id\", \"complex-data\", \"performance-test\"]
                },
                \"outputs\": [\"postgres-threshold-test\"]
            }" > /dev/null 2>&1; then
            ((success_count++))
        fi
    done
    
    echo "$success_count"
}

# Run controlled load test
echo "🚀 Starting PostgreSQL controlled threshold test..."
total_start=$(date +%s)
total_sent=0
total_success=0
error_count=0

for second in $(seq 1 $TEST_DURATION); do
    second_start=$(date +%s.%3N)
    second_success=0
    
    # Send batches for this second
    for batch in $(seq 1 $BATCHES_PER_SECOND); do
        batch_start=$(date +%s.%3N)
        
        success=$(send_controlled_batch "$second-$batch")
        second_success=$((second_success + success))
        total_success=$((total_success + success))
        total_sent=$((total_sent + BATCH_SIZE))
        
        if [ $success -lt $BATCH_SIZE ]; then
            error_count=$((error_count + BATCH_SIZE - success))
        fi
        
        # Sleep to maintain rate
        batch_end=$(date +%s.%3N)
        batch_duration=$(echo "$batch_end - $batch_start" | bc)
        sleep_time=$(echo "$SLEEP_BETWEEN_BATCHES - $batch_duration" | bc)
        
        if (( $(echo "$sleep_time > 0" | bc -l) )); then
            sleep $sleep_time
        fi
    done
    
    # Progress report every 15 seconds
    if [ $((second % 15)) -eq 0 ]; then
        success_rate=$(echo "scale=1; $second_success * 100 / $EVENTS_PER_SECOND" | bc)
        echo "Second $second: ${second_success}/${EVENTS_PER_SECOND} events (${success_rate}% success)"
    fi
done

total_end=$(date +%s)
actual_duration=$((total_end - total_start))

echo ""
echo "📊 POSTGRESQL THRESHOLD TEST RESULTS:"
echo "- Target events: $TOTAL_EVENTS"
echo "- Events sent: $total_sent"
echo "- Events successful: $total_success"
echo "- Events failed: $error_count"
echo "- Success rate: $(echo "scale=1; $total_success * 100 / $total_sent" | bc)%"
echo "- Actual duration: ${actual_duration}s"
echo "- Actual rate: $(echo "scale=1; $total_success / $actual_duration" | bc) events/sec"

# Test functionality after sustained load
echo ""
echo "🔍 Testing PostgreSQL functionality after sustained load..."

# Search test
search_start=$(date +%s.%3N)
search_result=$(curl -s -u admin:admin "http://$TARGET/api/v1/events/search?limit=20&priority=Critical")
search_end=$(date +%s.%3N)
search_time=$(echo "$search_end - $search_start" | bc)

if echo "$search_result" | jq -e '.statistics' > /dev/null 2>&1; then
    event_count=$(echo "$search_result" | jq -r '.statistics.all')
    returned_count=$(echo "$search_result" | jq -r '.statistics.returned')
    echo "✅ Search functional: $returned_count/$event_count events (${search_time}s response)"
else
    echo "❌ Search failed after load test"
fi

# Complex aggregation test
agg_start=$(date +%s.%3N)
agg_result=$(curl -s -u admin:admin "http://$TARGET/api/v1/events/count/source")
agg_end=$(date +%s.%3N)
agg_time=$(echo "$agg_end - $agg_start" | bc)

if echo "$agg_result" | jq -e '.statistics' > /dev/null 2>&1; then
    distinct_count=$(echo "$agg_result" | jq -r '.statistics.distincts')
    echo "✅ Source aggregation functional: $distinct_count distinct sources (${agg_time}s response)"
    echo "$agg_result" | jq -r '.results | to_entries[] | "\(.key): \(.value)"' | head -5
else
    echo "❌ Aggregation failed after load test"
fi

# Test filtering performance
filter_start=$(date +%s.%3N)
filter_result=$(curl -s -u admin:admin "http://$TARGET/api/v1/events/search?priority=Critical,Alert&source=k8s&limit=10")
filter_end=$(date +%s.%3N)
filter_time=$(echo "$filter_end - $filter_start" | bc)

if echo "$filter_result" | jq -e '.statistics' > /dev/null 2>&1; then
    filtered_count=$(echo "$filter_result" | jq -r '.statistics.returned')
    echo "✅ Complex filtering functional: $filtered_count results (${filter_time}s response)"
else
    echo "❌ Filtering failed after load test"
fi

echo ""
echo "🎯 PostgreSQL Threshold Test Complete!"
echo "Backend PID: $BACKEND_PID (kill with: kill $BACKEND_PID)"

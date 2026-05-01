import boto3

region = "ca-central-1"
fn = "ccvideo-default-video-trigger"
captions_bucket = "ccvideo-default-118922137804-captions"
sm_arn = "arn:aws:states:ca-central-1:118922137804:stateMachine:ccvideo-default-caption-pipeline"

lc  = boto3.client("lambda",        region_name=region)
s3  = boto3.client("s3",            region_name=region)
sfn = boto3.client("stepfunctions", region_name=region)

# Lambda env vars + metadata
cfg = lc.get_function_configuration(FunctionName=fn)
print("=== LAMBDA ENV VARS ===")
for k, v in cfg.get("Environment", {}).get("Variables", {}).items():
    print(f"  {k} = {v}")
print(f"  Runtime      : {cfg['Runtime']}")
print(f"  LastModified : {cfg['LastModified']}")
print(f"  Handler      : {cfg['Handler']}")

# S3 notification
print()
print("=== S3 NOTIFICATION (captions bucket) ===")
notif = s3.get_bucket_notification_configuration(Bucket=captions_bucket)
fns = notif.get("LambdaFunctionConfigurations", [])
if fns:
    for lf in fns:
        print(f"  LambdaArn : {lf['LambdaFunctionArn']}")
        print(f"  Events    : {lf['Events']}")
        print(f"  Filter    : {lf.get('Filter', 'none')}")
else:
    print("  *** NO LAMBDA NOTIFICATION CONFIGURED ON THIS BUCKET ***")

# Step Functions executions
print()
print("=== RECENT STEP FUNCTIONS EXECUTIONS (last 5) ===")
execs = sfn.list_executions(stateMachineArn=sm_arn, maxResults=5)
for e in execs.get("executions", []):
    print(f"  {e['name']} | {e['status']} | {e['startDate']}")
if not execs.get("executions"):
    print("  *** NO EXECUTIONS FOUND ***")

# Deploy updated Lambda code
print()
print("=== DEPLOYING UPDATED LAMBDA CODE ===")
with open("lambda/trigger.zip", "rb") as f:
    zb = f.read()
resp = lc.update_function_code(FunctionName=fn, ZipFile=zb)
print(f"  CodeSize     : {resp['CodeSize']} bytes")
print(f"  LastModified : {resp['LastModified']}")
print(f"  State        : {resp.get('State', 'n/a')}")
print("  *** New logging code deployed successfully ***")

# Fix Lambda env vars
print()
print("=== UPDATING LAMBDA ENV VARS ===")
env_resp = lc.update_function_configuration(
    FunctionName=fn,
    Environment={
        "Variables": {
            "STATE_MACHINE_ARN": sm_arn,
            "CAPTIONS_BUCKET":   "ccvideo-default-118922137804-input",
            "OUTPUT_PREFIX":     "captions/",
        }
    },
)
for k, v in env_resp.get("Environment", {}).get("Variables", {}).items():
    print(f"  {k} = {v}")

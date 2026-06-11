"""
azure-pipeline-lab — Phase 3 stub function.

Blob trigger on `inbox/` -> upsert one row to the tickets table (id, time,
size) -> copy blob to `completed/` -> delete from `inbox/`. ~30 lines.

The mesh, classifier, and dashboard logic stay home (in MncRydr). This
file exists to prove the round trip works end-to-end on Azure primitives.
"""
import logging
import os
from datetime import datetime, timezone

import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.data.tables import TableServiceClient
from azure.storage.blob import BlobServiceClient

STORAGE_ACCOUNT = os.environ["QUEUE_STORAGE_ACCOUNT"]
INBOX = os.environ["INBOX_CONTAINER"]
COMPLETED = os.environ["COMPLETED_CONTAINER"]
TICKETS_TABLE = os.environ["TICKETS_TABLE"]

credential = DefaultAzureCredential()
table_client = TableServiceClient(
    endpoint=f"https://{STORAGE_ACCOUNT}.table.core.windows.net/",
    credential=credential,
).get_table_client(TICKETS_TABLE)
blob_service = BlobServiceClient(
    account_url=f"https://{STORAGE_ACCOUNT}.blob.core.windows.net/",
    credential=credential,
)

app = func.FunctionApp()


@app.blob_trigger(arg_name="blob", path=f"{INBOX}/{{name}}", connection="AzureWebJobsStorage")
def route_ticket(blob: func.InputStream) -> None:
    name = blob.name.split("/", 1)[1]
    ticket_id = os.path.splitext(name)[0]

    table_client.upsert_entity({
        "PartitionKey": "tickets",
        "RowKey": ticket_id,
        "BlobName": name,
        "IngestedAt": datetime.now(timezone.utc).isoformat(),
        "SizeBytes": blob.length,
    })

    src = blob_service.get_blob_client(INBOX, name)
    dst = blob_service.get_blob_client(COMPLETED, name)
    dst.start_copy_from_url(src.url)
    src.delete_blob()

    logging.info("routed %s -> %s; recorded in %s", name, COMPLETED, TICKETS_TABLE)

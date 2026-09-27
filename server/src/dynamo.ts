import {
  ConditionalCheckFailedException, DynamoDBClient, GetItemCommand, UpdateItemCommand,
} from "@aws-sdk/client-dynamodb";
import type { QuotaStore } from "./quota.js";

/**
 * Quota counters in DynamoDB: one item per counter (`pk`), updated atomically
 * with a conditional ADD so two requests can never both take the last TL;DR.
 * `expiresAt` (epoch seconds) is the table's TTL attribute, so old counters
 * delete themselves.
 */
export class DynamoQuotaStore implements QuotaStore {
  constructor(private table: string, private client = new DynamoDBClient({})) {}

  async consume(key: string, limit: number, expiresAt: Date) {
    try {
      const result = await this.client.send(new UpdateItemCommand({
        TableName: this.table,
        Key: { pk: { S: key } },
        UpdateExpression: "ADD #c :one SET expiresAt = :exp",
        ConditionExpression: "attribute_not_exists(#c) OR #c < :limit",
        ExpressionAttributeNames: { "#c": "count" },
        ExpressionAttributeValues: {
          ":one": { N: "1" },
          ":limit": { N: String(limit) },
          ":exp": { N: String(Math.floor(expiresAt.getTime() / 1000)) },
        },
        ReturnValues: "UPDATED_NEW",
      }));
      return { allowed: true, count: Number(result.Attributes?.count?.N ?? 1) };
    } catch (error) {
      if (error instanceof ConditionalCheckFailedException) return { allowed: false, count: await this.count(key) };
      throw error;
    }
  }

  async refund(key: string) {
    try {
      await this.client.send(new UpdateItemCommand({
        TableName: this.table,
        Key: { pk: { S: key } },
        UpdateExpression: "ADD #c :minus",
        ConditionExpression: "#c > :zero",
        ExpressionAttributeNames: { "#c": "count" },
        ExpressionAttributeValues: { ":minus": { N: "-1" }, ":zero": { N: "0" } },
      }));
    } catch (error) {
      if (!(error instanceof ConditionalCheckFailedException)) throw error;
    }
  }

  async count(key: string) {
    const item = await this.client.send(new GetItemCommand({
      TableName: this.table, Key: { pk: { S: key } }, ConsistentRead: true,
    }));
    return Number(item.Item?.count?.N ?? 0);
  }
}

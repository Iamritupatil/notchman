import {
  ConditionalCheckFailedException, DynamoDBClient, GetItemCommand, PutItemCommand, UpdateItemCommand,
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

  async consume(key: string, limit: number, expiresAt: Date, amount = 1) {
    if (amount > limit) return { allowed: false, count: await this.count(key) };
    try {
      const result = await this.client.send(new UpdateItemCommand({
        TableName: this.table,
        Key: { pk: { S: key } },
        UpdateExpression: "ADD #c :amount SET expiresAt = :exp",
        ConditionExpression: "attribute_not_exists(#c) OR #c <= :max",
        ExpressionAttributeNames: { "#c": "count" },
        ExpressionAttributeValues: {
          ":amount": { N: String(amount) },
          ":max": { N: String(limit - amount) },
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

  async refund(key: string, amount = 1) {
    try {
      await this.client.send(new UpdateItemCommand({
        TableName: this.table,
        Key: { pk: { S: key } },
        UpdateExpression: "ADD #c :minus",
        ConditionExpression: "#c >= :amount",
        ExpressionAttributeNames: { "#c": "count" },
        ExpressionAttributeValues: { ":minus": { N: String(-amount) }, ":amount": { N: String(amount) } },
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

  async getRecord(key: string) {
    const item = await this.client.send(new GetItemCommand({
      TableName: this.table, Key: { pk: { S: key } }, ConsistentRead: true,
    }));
    const data = item.Item?.data?.S;
    if (!data) return null;
    try { return JSON.parse(data) as Record<string, unknown>; } catch { return null; }
  }

  async putRecord(key: string, value: Record<string, unknown>, expiresAt: Date) {
    await this.client.send(new PutItemCommand({
      TableName: this.table,
      Item: {
        pk: { S: key },
        data: { S: JSON.stringify(value) },
        expiresAt: { N: String(Math.floor(expiresAt.getTime() / 1000)) },
      },
    }));
  }
}

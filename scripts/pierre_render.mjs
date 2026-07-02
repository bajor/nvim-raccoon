#!/usr/bin/env node
import { stdin, stdout, stderr, exit } from "node:process";
import { Buffer } from "node:buffer";

function cleanLine(value) {
  return String(value ?? "").replace(/\r?\n$/, "");
}

function byteLength(value) {
  return Buffer.byteLength(value, "utf8");
}

function deletedChunks(oldText, newText, diffWordsWithSpace) {
  if (typeof diffWordsWithSpace !== "function") {
    return [{ text: `- ${oldText}`, hl: "RaccoonDelete" }];
  }

  const chunks = [{ text: "- ", hl: "RaccoonDelete" }];
  for (const part of diffWordsWithSpace(oldText, newText)) {
    if (part.added) {
      continue;
    }
    chunks.push({
      text: part.value,
      hl: part.removed ? "RaccoonDeleteInline" : "RaccoonDelete",
    });
  }
  return chunks;
}

function addedSpans(oldText, newText, lineNum, diffWordsWithSpace) {
  if (typeof diffWordsWithSpace !== "function") {
    return [];
  }

  const spans = [];
  let col = 0;
  for (const part of diffWordsWithSpace(oldText, newText)) {
    if (part.removed) {
      continue;
    }

    const width = byteLength(part.value);
    if (part.added && width > 0) {
      spans.push({
        line_num: lineNum,
        start_col: col,
        end_col: col + width,
      });
    }
    col += width;
  }
  return spans;
}

async function readStdin() {
  let body = "";
  for await (const chunk of stdin) {
    body += chunk;
  }
  return body;
}

async function main() {
  let input;
  try {
    input = JSON.parse((await readStdin()) || "{}");
  } catch {
    stderr.write("invalid input json\n");
    exit(1);
  }

  let parsePatchFiles;
  try {
    ({ parsePatchFiles } = await import("@pierre/diffs"));
  } catch {
    stderr.write("missing @pierre/diffs\n");
    exit(1);
  }

  let diffWordsWithSpace;
  if (input.inline_word_diff !== false) {
    try {
      ({ diffWordsWithSpace } = await import("diff"));
    } catch {
      diffWordsWithSpace = undefined;
    }
  }

  let patches;
  try {
    patches = parsePatchFiles(String(input.patch || ""));
  } catch {
    stderr.write("failed to parse patch\n");
    exit(1);
  }

  const fileDiff = patches?.[0]?.files?.[0];
  if (!fileDiff) {
    stdout.write(
      JSON.stringify({
        version: 1,
        hunks: [],
        added: [],
        deleted: [],
        reviewable: [],
        inline_add: [],
      })
    );
    return;
  }

  const added = [];
  const deleted = [];
  const reviewable = new Set();
  const inlineAdd = [];
  const hunks = [];

  for (const hunk of fileDiff.hunks || []) {
    const hunkStart = Math.max(hunk.additionStart || 1, 1);
    hunks.push({
      start_line: hunkStart,
      end_line: hunkStart + Math.max(hunk.additionCount || 0, 1) - 1,
    });

    let addIdx = hunk.additionLineIndex || 0;
    let delIdx = hunk.deletionLineIndex || 0;
    let anchor = hunkStart;

    for (const part of hunk.hunkContent || []) {
      if (part.type === "context") {
        for (let i = 0; i < part.lines; i++) {
          reviewable.add(anchor + i);
        }
        addIdx += part.lines;
        delIdx += part.lines;
        anchor += part.lines;
        continue;
      }

      const rows = [];
      const pairedRows = Math.min(part.deletions, part.additions);
      for (let i = 0; i < part.deletions; i++) {
        const oldText = cleanLine(fileDiff.deletionLines?.[delIdx + i]);
        const newText =
          i < pairedRows ? cleanLine(fileDiff.additionLines?.[addIdx + i]) : "";
        rows.push(deletedChunks(oldText, newText, diffWordsWithSpace));
      }
      if (rows.length > 0) {
        deleted.push({ line_num: Math.max(anchor, 1), rows });
      }

      for (let i = 0; i < part.additions; i++) {
        const lineNum = anchor + i;
        added.push(lineNum);
        reviewable.add(lineNum);
        if (i < pairedRows) {
          inlineAdd.push(
            ...addedSpans(
              cleanLine(fileDiff.deletionLines?.[delIdx + i]),
              cleanLine(fileDiff.additionLines?.[addIdx + i]),
              lineNum,
              diffWordsWithSpace
            )
          );
        }
      }

      addIdx += part.additions;
      delIdx += part.deletions;
      anchor += part.additions;
    }
  }

  stdout.write(
    JSON.stringify({
      version: 1,
      hunks,
      added,
      deleted,
      reviewable: Array.from(reviewable).sort((a, b) => a - b),
      inline_add: inlineAdd,
    })
  );
}

main().catch((err) => {
  stderr.write(`${String(err)}\n`);
  exit(1);
});

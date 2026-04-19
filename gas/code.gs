/**
 * POST リクエストを受け取り、DailyActivity シートに書き込む。
 * 各 username × date の組み合わせで行を upsert する。
 */
function doPost(e) {
  try {
    var data = JSON.parse(e.postData.contents);
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName("DailyActivity");
    if (!sheet) {
      return ContentService.createTextOutput(JSON.stringify({ status: "error", message: "Sheet not found" }))
        .setMimeType(ContentService.MimeType.JSON);
    }

    var now = new Date().toISOString();
    var username = data.username || "unknown";
    var hostname = data.hostname || "unknown";
    var dailyActivity = data.dailyActivity || [];
    var dailyModelTokens = data.dailyModelTokens || [];

    // dailyModelTokens を date でインデックス化
    var tokensByDate = {};
    for (var i = 0; i < dailyModelTokens.length; i++) {
      tokensByDate[dailyModelTokens[i].date] = JSON.stringify(dailyModelTokens[i].tokensByModel || {});
    }

    // 既存データを読み込み（username + date で upsert するため）
    var lastRow = sheet.getLastRow();
    var existingRows = {};
    if (lastRow > 1) {
      var values = sheet.getRange(2, 1, lastRow - 1, 8).getValues();
      for (var r = 0; r < values.length; r++) {
        var key = values[r][1] + "|" + values[r][3]; // username|date
        existingRows[key] = r + 2; // 行番号（1-indexed, ヘッダー分+1）
      }
    }

    // dailyActivity の各日を upsert
    for (var j = 0; j < dailyActivity.length; j++) {
      var day = dailyActivity[j];
      var row = [
        now,
        username,
        hostname,
        day.date,
        day.messageCount || 0,
        day.sessionCount || 0,
        day.toolCallCount || 0,
        tokensByDate[day.date] || "{}"
      ];

      var key = username + "|" + day.date;
      if (existingRows[key]) {
        // 既存行を更新
        sheet.getRange(existingRows[key], 1, 1, 8).setValues([row]);
      } else {
        // 新規行を追加
        sheet.appendRow(row);
      }
    }

    return ContentService.createTextOutput(JSON.stringify({ status: "ok", rows: dailyActivity.length }))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({ status: "error", message: err.message }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

/**
 * 週次ランキングを Slack に送信する。
 * GAS のトリガーで毎週実行する（例: 毎週月曜 10:00）。
 */
function sendWeeklyRanking() {
  var webhookUrl = PropertiesService.getScriptProperties().getProperty("SLACK_WEBHOOK_URL");
  if (!webhookUrl) {
    Logger.log("SLACK_WEBHOOK_URL が設定されていません");
    return;
  }

  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName("DailyActivity");
  if (!sheet) return;

  var lastRow = sheet.getLastRow();
  if (lastRow <= 1) return;

  // 過去 7 日分の日付範囲を計算
  var now = new Date();
  var weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  var startDate = Utilities.formatDate(weekAgo, Session.getScriptTimeZone(), "yyyy-MM-dd");
  var endDate = Utilities.formatDate(now, Session.getScriptTimeZone(), "yyyy-MM-dd");

  var values = sheet.getRange(2, 1, lastRow - 1, 8).getValues();

  // username ごとに集計
  var stats = {};
  for (var i = 0; i < values.length; i++) {
    var date = values[i][3];
    // date が Date オブジェクトの場合に対応
    if (date instanceof Date) {
      date = Utilities.formatDate(date, Session.getScriptTimeZone(), "yyyy-MM-dd");
    }
    if (date < startDate || date > endDate) continue;

    var username = values[i][1];
    if (!stats[username]) {
      stats[username] = { tokens: 0, messages: 0 };
    }

    stats[username].messages += (values[i][4] || 0); // messageCount

    // tokensByModel (JSON) からトークン合計を算出
    var tokensJson = values[i][7] || "{}";
    try {
      var tokensByModel = JSON.parse(tokensJson);
      for (var model in tokensByModel) {
        stats[username].tokens += tokensByModel[model];
      }
    } catch (e) {
      // パース失敗は無視
    }
  }

  // トークン数で降順ソート
  var ranking = Object.keys(stats).map(function(username) {
    return { username: username, tokens: stats[username].tokens, messages: stats[username].messages };
  }).sort(function(a, b) {
    return b.tokens - a.tokens;
  });

  if (ranking.length === 0) {
    Logger.log("データなし: ランキング送信をスキップ");
    return;
  }

  // Slack メッセージを組み立て
  var medals = ["🥇", "🥈", "🥉"];
  var lines = ranking.map(function(r, i) {
    var prefix = i < 3 ? medals[i] : (i + 1) + ".";
    return prefix + " " + r.username + " — " + formatTokens(r.tokens) + " tokens (" + r.messages.toLocaleString() + " messages)";
  });

  var text = "📊 *Weekly Claude Code Ranking* (" + startDate + " 〜 " + endDate + ")\n\n" + lines.join("\n");

  // Slack に送信
  UrlFetchApp.fetch(webhookUrl, {
    method: "post",
    contentType: "application/json",
    payload: JSON.stringify({ text: text })
  });

  Logger.log("ランキングを送信しました: " + ranking.length + " users");
}

/**
 * トークン数を読みやすい形式にフォーマットする。
 * 例: 1234567 → "1,234,567"
 */
function formatTokens(num) {
  return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

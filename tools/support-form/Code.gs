/**
 * RainPulse support form mailer.
 * Deployed as a Google Apps Script web app owned by rainpulse3@gmail.com
 * (Execute as: Me, Who has access: Anyone). The website's support form posts
 * here; each valid request is emailed to TO with the sender as Reply-To.
 */
const TO = 'rainpulse3@gmail.com';
const MAX_FILES = 3;
const MAX_FILE_BYTES = 5 * 1024 * 1024;     // 5 MB per file
const MAX_TOTAL_BYTES = 10 * 1024 * 1024;   // 10 MB for all files together
const MAX_PER_EMAIL_PER_HOUR = 5;
const MAX_PER_DAY = 80;                     // Gmail consumer quota is 100 emails/day
const TYPES = /^(image\/(png|jpeg|heic|heif|gif|webp)|application\/pdf|text\/plain|video\/(mp4|quicktime))$/;
const TOPICS = ['Bug or crash', 'Subscription or payment', 'Rain alerts or warnings', 'Wrong forecast', 'Feature idea', 'Privacy or my data', 'Other'];

function doPost(e) {
  try {
    const d = JSON.parse(e.postData.contents);
    if (d.website) return out({ ok: true });                       // honeypot: bots fill hidden field
    if (Date.now() - Number(d.t || 0) < 4000) return fail('Please take a moment to fill in the form, then send again.');

    const email = clean(d.email, 200);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return fail('Enter a valid email address so we can reply.');
    const message = clean(d.message, 5000);
    if (message.length < 10) return fail('Describe the problem in a few words (at least 10 characters).');
    const name = clean(d.name, 100);
    const topic = TOPICS.indexOf(d.topic) >= 0 ? d.topic : 'Other';
    const device = clean(d.device, 200);
    const appVersion = clean(d.appVersion, 40);

    const files = Array.isArray(d.files) ? d.files : [];
    if (files.length > MAX_FILES) return fail('Attach up to ' + MAX_FILES + ' files.');
    let total = 0;
    const attachments = files.map(function (f) {
      const type = String(f.type || '');
      if (!TYPES.test(type)) throw new UserError('"' + clean(f.name, 80) + '" is not a supported file type.');
      const bytes = Utilities.base64Decode(String(f.data || ''));
      if (bytes.length > MAX_FILE_BYTES) throw new UserError('"' + clean(f.name, 80) + '" is larger than 5 MB.');
      total += bytes.length;
      return Utilities.newBlob(bytes, type, clean(f.name, 120) || 'attachment');
    });
    if (total > MAX_TOTAL_BYTES) return fail('Attachments add up to more than 10 MB. Remove or shrink a file.');

    // Rate limits
    const cache = CacheService.getScriptCache();
    const key = 'e:' + email.toLowerCase();
    const sent = Number(cache.get(key) || 0);
    if (sent >= MAX_PER_EMAIL_PER_HOUR) return fail('You have sent several requests in the last hour. Please wait and try again later.');
    const lock = LockService.getScriptLock(); lock.waitLock(10000);
    const props = PropertiesService.getScriptProperties();
    const day = Utilities.formatDate(new Date(), 'Asia/Kolkata', 'yyyy-MM-dd');
    const today = props.getProperty('day') === day ? Number(props.getProperty('count') || 0) : 0;
    if (today >= MAX_PER_DAY) { lock.releaseLock(); return fail('Support is very busy today. Please try again tomorrow.'); }
    props.setProperties({ day: day, count: String(today + 1) });
    lock.releaseLock();
    cache.put(key, String(sent + 1), 3600);

    const ref = 'RP-' + Utilities.formatDate(new Date(), 'Asia/Kolkata', 'yyMMdd') + '-' + Math.random().toString(36).slice(2, 6).toUpperCase();
    const body = [
      'Reference: ' + ref,
      'Topic: ' + topic,
      'From: ' + (name || '(no name)') + ' <' + email + '>',
      'Device: ' + (device || '(not given)'),
      'App version: ' + (appVersion || '(not given)'),
      'Attachments: ' + (attachments.length ? attachments.map(function (a) { return a.getName(); }).join(', ') : 'none'),
      '',
      message,
      '',
      '— Sent from the RainPulse support form. Reply to this email to answer ' + email + '.'
    ].join('\n');

    MailApp.sendEmail({
      to: TO,
      replyTo: email,
      name: 'RainPulse Support Form',
      subject: '[RainPulse] ' + topic + ' – ' + (name || email) + ' (' + ref + ')',
      body: body,
      attachments: attachments
    });
    return out({ ok: true, ref: ref });
  } catch (err) {
    if (err instanceof UserError) return fail(err.message);
    console.error(err);
    return fail('The message could not be sent. Please try again in a few minutes.');
  }
}

function doGet() { return out({ ok: true, service: 'RainPulse support' }); }

function UserError(message) { this.message = message; }
function clean(v, max) { return String(v == null ? '' : v).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '').trim().slice(0, max); }
function fail(error) { return out({ ok: false, error: error }); }
function out(o) { return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON); }

/** Run once from the editor to grant the "send email" permission. */
function authorize() { MailApp.getRemainingDailyQuota(); }

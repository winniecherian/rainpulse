// Support form: sends to a Google Apps Script web app owned by rainpulse3@gmail.com,
// which emails the request (with attachments) to that inbox.
const ENDPOINT = "SCRIPT_URL_HERE";
const FALLBACK_EMAIL = "rainpulse3@gmail.com";
const MAX_FILES = 3, MAX_FILE = 5 * 1024 * 1024, MAX_TOTAL = 10 * 1024 * 1024;
const TYPES = /^(image\/(png|jpeg|heic|heif|gif|webp)|application\/pdf|text\/plain|video\/(mp4|quicktime))$/;
const EXT_TYPES = { heic: "image/heic", heif: "image/heif", mov: "video/quicktime", txt: "text/plain", log: "text/plain" };

const form = document.getElementById("support-form");
const fileInput = document.getElementById("files");
const list = document.getElementById("file-list");
const drop = document.getElementById("drop");
const errorBox = document.getElementById("form-error");
const sendBtn = document.getElementById("send");
const sent = document.getElementById("sent");
const startedAt = Date.now();
let chosen = [];

// Prefill device from an iPhone browser, as a starting point the person can edit.
const ua = navigator.userAgent.match(/iPhone OS (\d+)_(\d+)/);
if (ua && !form.device.value) form.device.value = `iPhone, iOS ${ua[1]}.${ua[2]}`;

const fmt = b => b < 1024 * 1024 ? `${Math.max(1, Math.round(b / 1024))} KB` : `${(b / 1048576).toFixed(1)} MB`;
const typeOf = f => f.type || EXT_TYPES[(f.name.split(".").pop() || "").toLowerCase()] || "";
const showError = msg => { errorBox.textContent = msg; };

function addFiles(files) {
  showError("");
  for (const f of files) {
    if (chosen.length >= MAX_FILES) { showError(`You can attach up to ${MAX_FILES} files.`); break; }
    if (!TYPES.test(typeOf(f))) { showError(`"${f.name}" can't be attached. Use an image, PDF, text file or short video.`); continue; }
    if (f.size > MAX_FILE) { showError(`"${f.name}" is ${fmt(f.size)}. Each file must be 5 MB or smaller.`); continue; }
    if (chosen.reduce((s, x) => s + x.size, 0) + f.size > MAX_TOTAL) { showError("Files can add up to 10 MB in total. Remove one or attach a smaller file."); continue; }
    if (chosen.some(x => x.name === f.name && x.size === f.size)) continue;
    chosen.push(f);
  }
  render();
}

function render() {
  list.innerHTML = "";
  chosen.forEach((f, i) => {
    const li = document.createElement("li");
    const name = document.createElement("span");
    name.textContent = f.name;
    const size = document.createElement("small"); size.textContent = fmt(f.size); name.appendChild(size);
    const rm = document.createElement("button");
    rm.type = "button"; rm.textContent = "Remove"; rm.setAttribute("aria-label", `Remove ${f.name}`);
    rm.onclick = () => { chosen.splice(i, 1); showError(""); render(); };
    li.append(name, rm); list.appendChild(li);
  });
  drop.querySelector("span").textContent = chosen.length >= MAX_FILES ? "3 files attached (the maximum)" : chosen.length ? "Add another file" : "Choose files or drop them here";
  fileInput.disabled = chosen.length >= MAX_FILES;
}

fileInput.addEventListener("change", () => { addFiles([...fileInput.files]); fileInput.value = ""; });
["dragenter", "dragover"].forEach(ev => drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.add("over"); }));
["dragleave", "drop"].forEach(ev => drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.remove("over"); }));
drop.addEventListener("drop", e => addFiles([...e.dataTransfer.files]));

const toBase64 = f => new Promise((res, rej) => {
  const r = new FileReader();
  r.onload = () => res(String(r.result).split(",")[1] || "");
  r.onerror = () => rej(new Error(`Couldn't read "${f.name}".`));
  r.readAsDataURL(f);
});

form.addEventListener("submit", async e => {
  e.preventDefault();
  showError("");
  form.querySelectorAll("[aria-invalid]").forEach(el => el.removeAttribute("aria-invalid"));
  const email = form.email.value.trim(), message = form.message.value.trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) { form.email.setAttribute("aria-invalid", "true"); form.email.focus(); return showError("Enter a valid email address so we can reply."); }
  if (message.length < 10) { form.message.setAttribute("aria-invalid", "true"); form.message.focus(); return showError("Describe the problem in a few words (at least 10 characters)."); }

  sendBtn.disabled = true;
  sendBtn.textContent = chosen.length ? "Uploading files…" : "Sending…";
  try {
    const files = await Promise.all(chosen.map(async f => ({ name: f.name, type: typeOf(f), data: await toBase64(f) })));
    sendBtn.textContent = "Sending…";
    const payload = {
      name: form.name.value, email, topic: form.topic.value, message,
      device: form.device.value, appVersion: form.appVersion.value,
      website: form.website.value, t: startedAt, files
    };
    // text/plain keeps this a "simple" request, which Apps Script accepts without a CORS preflight.
    const res = await fetch(ENDPOINT, { method: "POST", body: JSON.stringify(payload), headers: { "Content-Type": "text/plain;charset=utf-8" } });
    const data = await res.json();
    if (!data.ok) throw new Error(data.error || "The message could not be sent.");
    document.getElementById("ref").textContent = data.ref || "";
    document.getElementById("sent-email").textContent = email;
    form.hidden = true; sent.hidden = false; sent.focus();
  } catch (err) {
    const msg = err instanceof TypeError || err instanceof SyntaxError
      ? `The message couldn't be sent. Check your connection and try again, or email ${FALLBACK_EMAIL}.`
      : err.message;
    showError(msg);
  } finally {
    sendBtn.disabled = false; sendBtn.textContent = "Send message";
  }
});

document.getElementById("again").addEventListener("click", () => {
  form.reset(); chosen = []; render(); sent.hidden = true; form.hidden = false; form.message.focus();
});

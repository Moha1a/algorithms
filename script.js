
/* eslint-disable no-alert */
window.addEventListener("error", function (e) {
  console.error("Global Error:", e.message);
  try {
    const errBox = document.createElement("div");
    errBox.style.cssText = "position:fixed;bottom:10px;left:10px;background:#ffdddd;padding:10px;border-radius:8px;font-size:12px;z-index:9999;";
    errBox.textContent = "حدث خطأ بالنظام";
    document.body.appendChild(errBox);
  } catch (_) {}
});

// ==========================================
// Firebase + Firestore Financial Booking SPA
// ==========================================
import { initializeApp } from "https://www.gstatic.com/firebasejs/9.23.0/firebase-app.js";
import {
getAuth,
onAuthStateChanged,
signInWithEmailAndPassword,
createUserWithEmailAndPassword,
signOut,
setPersistence,
browserLocalPersistence,
GoogleAuthProvider,
signInWithPopup,
signInWithRedirect,
getRedirectResult } from
"https://www.gstatic.com/firebasejs/9.23.0/firebase-auth.js";
import { getMessaging, getToken as getFcmToken, onMessage as onFcmMessage } from "https://www.gstatic.com/firebasejs/9.23.0/firebase-messaging.js";
import {
getFirestore,
doc,
setDoc,
getDoc,
updateDoc,
deleteDoc,
runTransaction,
collection,
addDoc,
onSnapshot,
query,
where,
arrayUnion,
orderBy,
increment,
serverTimestamp,
getDocs,
limit,
collectionGroup } from
"https://www.gstatic.com/firebasejs/9.23.0/firebase-firestore.js";

// Firestore Security Rules (example):
// rules_version = '2';
// service cloud.firestore { match /databases/{db}/documents {
//   match /users/{uid} { allow read, write: if request.auth != null && request.auth.uid == uid; allow delete: if request.auth.token.admin == true; }
//   match /bookings/{id} {
//     allow create: if request.auth != null && get(/databases/$(db)/documents/users/$(request.auth.uid)).data.role == 'client';
//     allow update: if request.auth != null && (
//       resource.data.clientId == request.auth.uid || resource.data.outletId == request.auth.uid || request.auth.token.admin == true
//     );
//     allow read: if request.auth != null;
//   }
//   match /ratings/{id} {
//     allow read: if request.auth != null && (resource.data.fromUserId == request.auth.uid || request.auth.token.admin == true);
//     allow create: if request.auth != null;
//   }
// }}

const firebaseConfig = {
  apiKey: "AIzaSyDTzOzJCTsGZBEriGQEOtU9218lenRT02I",
  authDomain: "qiqa-c17c2.firebaseapp.com",
  projectId: "qiqa-c17c2",
  storageBucket: "qiqa-c17c2.firebasestorage.app",
  messagingSenderId: "1025525101614",
  appId: "1:1025525101614:web:08c4c874f05d1713cfdbbf",
  measurementId: "G-B0L165W2VE" };


const GOOGLE_MAPS_API_KEY = "AIzaSyAYudrnmapDXgCc0_GQwkNAh7OBITIyoOA";
const ADMIN_EMAIL = "Amma1212@gmail.com";
const ADMIN_PASSWORD = "ALskQPwo0099@&";
const COMMISSION_RATE = 0.03;
const EXPIRY_MS = 5 * 60 * 60 * 1000;
const ACTIVE_BOOKING_LIMIT = 3;
const CREATE_RATE_LIMIT_MS = 10000;
const STRIPE_PUBLISHABLE_KEY = "pk_test_CHANGE_ME";
const FCM_VAPID_KEY = "BOw0wSCU4Hht9t9yips1yGL788tReovcPLu7327S70wnDTEoUQbRixVXJBhiequOUMOFDFdRLWLOcNZh345CC34";
const SUPPORT_CHAT_IDLE_MS = 10 * 60 * 1000;

const SPAM_LIMITS = {
  login: { limit: 8, windowMs: 10 * 60 * 1000 },
  register: { limit: 4, windowMs: 20 * 60 * 1000 },
  proposal: { limit: 10, windowMs: 20 * 60 * 1000 },
  message: { limit: 25, windowMs: 10 * 60 * 1000 }
};

let realtimeReady = false;
let realtimeUid = null;
let renderQueued = false;
let filterDebounceTimer = null;
let bookingSubmitBusy = false;
let lastCreateAt = 0;
let tokenCountdownInterval = null;
let mapCountdownInterval = null;
let mapCancelBusy = false;
const mapInstances = {};
let currentUserLocation = null;
let messaging = null;
let loadingCount = 0;
let rewardsCache = [];
let bookingChatUnsub = null;
let adminSupportChatUnsub = null;
const bookingStatusCache = new Map();

const outletSeedPoints = [
{ lat: 24.7136, lng: 46.6753 },
{ lat: 24.7411, lng: 46.6638 },
{ lat: 24.6935, lng: 46.7054 },
{ lat: 24.7259, lng: 46.6401 },
{ lat: 24.7022, lng: 46.6827 }];


const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const root = document.getElementById("app");
const APP_BOOT_LOG = "[QiqaAppBoot]";
const FETCH_TIMEOUT_MS = 12000;

if (!root) {
  console.error(`${APP_BOOT_LOG} #app element not found. App cannot render.`);
  const fallback = document.createElement("div");
  fallback.style.cssText = "position:fixed;inset:10px;z-index:9999;background:#fff2f2;color:#991b1b;padding:12px;border-radius:10px;font-family:Tajawal,Cairo,sans-serif;";
  fallback.textContent = "تعذر تشغيل التطبيق: عنصر العرض الرئيسي غير موجود (#app).";
  document.body.appendChild(fallback);
}

async function initAuthPersistence() {
  try {
    await setPersistence(auth, browserLocalPersistence);
    console.info(`${APP_BOOT_LOG} auth persistence initialized`);
  } catch (err) {
    console.warn(`${APP_BOOT_LOG} failed to set auth persistence`, err);
  }
}

function fetchWithTimeout(url, options = {}, timeoutMs = FETCH_TIMEOUT_MS) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  return fetch(url, { ...options, signal: ctrl.signal }).finally(() => clearTimeout(timer));
}

const state = {
  view: "role",
  role: null,
  tab: "requests",
  requestFilter: "running",
  modal: null,
  stars: 0,
  pending: null,
  user: null,
  users: [],
  outletRequests: [],
  bookings: [],
  ratings: [],
  supportMessages: [],
  supportChats: [],
  notifications: [],
  bookingMessages: [],
  toast: null,
  authDraft: { fullName: "", email: "", governorate: "البصرة", outletName: "", password: "", termsAccepted: false },
  bookingDraft: { type: "withdraw", amount: "", price: "" },
  unsubs: [] };


const uid = () => `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
const IRAQ_GOVERNORATES = ["بغداد", "البصرة", "نينوى", "أربيل", "النجف", "كربلاء", "بابل", "واسط", "ذي قار", "المثنى", "ميسان", "القادسية", "الأنبار", "صلاح الدين", "كركوك", "ديالى", "دهوك", "السليمانية"];

async function applySelectedPersistence() {
  await setPersistence(auth, browserLocalPersistence);
}

function governorateOptions(selected = "") {
  return IRAQ_GOVERNORATES.map(g => `<option value="${escapeHtml(g)}" ${selected === g ? "selected" : ""}>${escapeHtml(g)}</option>`).join("");
}

async function ensureUserProfileFromAuth(user, payload = {}) {
  if (!user?.uid) return null;
  const ref = doc(db, "users", user.uid);
  const snap = await getDoc(ref);
  if (snap.exists()) {
    const existing = snap.data();
    const payloadGov = String(payload.governorate || "").trim();
    const payloadPhone = String(payload.phone || "").trim();
    const updates = {};
    if (payloadGov && !String(existing.governorate || "").trim()) updates.governorate = payloadGov;
    if (payloadPhone && !String(existing.phone || "").trim()) updates.phone = payloadPhone;
    if (Object.keys(updates).length) {
      await updateDoc(ref, updates);
      return { ...existing, ...updates };
    }
    return existing;
  }
  const role = payload.role || state.role || "client";
  const fullName = payload.fullName || user.displayName || "مستخدم جديد";
  const governorate = payload.governorate || "";
  const outletName = role === "outlet" ? payload.outletName || user.displayName || fullName : "";
  await setDoc(ref, {
    uid: user.uid,
    role: role === "outlet" ? "pending" : role,
    fullName,
    email: user.email || "",
    outletName,
    ratingAverage: 0,
    totalOperations: 0,
    totalAmount: 0,
    governorate,
    phone: String(payload.phone || "").trim(),
    completedCount: 0,
    cancelledByUserCount: 0,
    cancelledByOtherCount: 0,
    totalAcceptedCount: 0,
    completionRate: 0,
    cancellationRate: 0,
    reputationScore: 0,
    adminBadge: "",
    adminBadgeText: "",
    adminBadgeIcon: "",
    badgeAssignedByAdmin: false,
    badgeAssignedAt: null,
    createdAt: serverTimestamp() });

  if (role === "outlet") {
    await setDoc(doc(db, "outletRequests", user.uid), {
      uid: user.uid,
      outletName,
      status: "pending",
      createdAt: serverTimestamp() });

  }
  await logAction(`${role}_register`, user.uid, { email: user.email || "" });
  return (await getDoc(ref)).data();
}

function requestRender() {
  if (renderQueued) return;
  renderQueued = true;
  setTimeout(() => {
    renderQueued = false;
    render();
  }, 16);
}

function setLoading(on) {
  loadingCount = Math.max(0, loadingCount + (on ? 1 : -1));
  requestRender();
}

function renderLoading() {
  return loadingCount > 0 ? '<div class="modal-wrap"><div class="modal"><p class="muted" style="text-align:center;">⏳ جاري التنفيذ...</p></div></div>' : "";
}

function formatNumber(num) {
  return Number(num || 0).toLocaleString("en-US");
}

function skeletonList() {
  return '<div class="item muted">...</div><div class="item muted">...</div><div class="item muted">...</div>';
}

function numberToArabicWords(amount) {
  const n = Math.floor(Number(amount || 0));
  if (!n) return "صفر دينار عراقي";
  const ones = ["", "واحد", "اثنان", "ثلاثة", "أربعة", "خمسة", "ستة", "سبعة", "ثمانية", "تسعة"];
  const tens = ["", "", "عشرون", "ثلاثون", "أربعون", "خمسون", "ستون", "سبعون", "ثمانون", "تسعون"];
  const teens = ["عشرة", "أحد عشر", "اثنا عشر", "ثلاثة عشر", "أربعة عشر", "خمسة عشر", "ستة عشر", "سبعة عشر", "ثمانية عشر", "تسعة عشر"];
  const hundreds = ["", "مائة", "مئتان", "ثلاثمائة", "أربعمائة", "خمسمائة", "ستمائة", "سبعمائة", "ثمانمائة", "تسعمائة"];
  const three = x => {
    const h = Math.floor(x / 100);
    const r = x % 100;
    let parts = [];
    if (h) parts.push(hundreds[h]);
    if (r >= 10 && r < 20) parts.push(teens[r - 10]);else
    {
      const t = Math.floor(r / 10);
      const o = r % 10;
      if (o) parts.push(ones[o]);
      if (t) parts.push(tens[t]);
    }
    return parts.filter(Boolean).join(" و");
  };
  const m = Math.floor(n / 1000000);
  const th = Math.floor(n % 1000000 / 1000);
  const rem = n % 1000;
  const parts = [];
  if (m) parts.push(`${three(m)} مليون`);
  if (th) parts.push(`${three(th)} ألف`);
  if (rem) parts.push(three(rem));
  return `${parts.join(" و")} دينار عراقي`;
}


function showToast(message, type = "info") {
  state.toast = { message: String(message || ""), type, at: Date.now() };
  requestRender();
  setTimeout(() => {
    if (state.toast && Date.now() - state.toast.at >= 6400) {
      state.toast = null;
      requestRender();
    }
  }, 6500);
}

function renderToast() {
  if (!state.toast?.message) return "";
  return `<div class="toast ${escapeHtml(state.toast.type || "info")}">${escapeHtml(state.toast.message)}</div>`;
}

function spamGuard(key, config = { limit: 5, windowMs: 10 * 60 * 1000 }) {
  const now = Date.now();
  const storageKey = `qiqa_spam_${key}`;
  let arr = [];
  try {arr = JSON.parse(localStorage.getItem(storageKey) || "[]");} catch (_) {arr = [];}
  arr = arr.filter(ts => now - Number(ts || 0) <= config.windowMs);
  if (arr.length >= config.limit) return false;
  arr.push(now);
  localStorage.setItem(storageKey, JSON.stringify(arr));
  return true;
}

function looksSuspiciousIdentity(fullName, email) {
  const n = String(fullName || "").trim();
  const e = String(email || "").toLowerCase();
  if (n.length < 6 || n.split(/\s+/).length < 2) return true;
  if (/\+\d{3,}/.test(e) || /test|fake|temp|spam/.test(e)) return true;
  return false;
}

async function notifyBookingParties(booking, type, title, body) {
  if (!booking) return;
  const ids = [...new Set([booking.clientId, booking.outletId, booking.createdById].filter(Boolean))];
  for (const id of ids) {
    await addNotification(id, type, booking.bookingId || booking.bookingDocId || "", title, body);
    await sendPushNotification(id, title, body, booking.bookingId || booking.bookingDocId || "");
  }
}

function authErrorAr(code) {
  return {
    "auth/email-already-in-use": "هذا البريد مسجل مسبقاً",
    "auth/invalid-email": "البريد الإلكتروني غير صحيح",
    "auth/account-exists-with-different-credential": "هذا البريد مرتبط بطريقة دخول مختلفة",
    "auth/popup-closed-by-user": "تم إغلاق نافذة تسجيل الدخول",
    "auth/popup-blocked": "المتصفح منع نافذة تسجيل الدخول",
    "auth/operation-not-supported-in-this-environment": "بيئة المتصفح لا تدعم Popup، سيتم التحويل التلقائي",
    "auth/operation-not-allowed": "طريقة تسجيل الدخول غير مفعّلة في Firebase",
    "auth/unauthorized-domain": "هذا الدومين غير مضاف في Authorized Domains داخل Firebase",
    "auth/weak-password": "كلمة السر ضعيفة (6 أحرف على الأقل)",
    "auth/user-not-found": "يرجى الضغط انشاء حساب لو كنت اول مرة تستخدم البرنامج",
    "auth/wrong-password": "كلمة السر غير صحيحة",
    "auth/invalid-credential": "يرجى الضغط انشاء حساب لو كنت اول مرة تستخدم البرنامج",
    "auth/role-mismatch": "الحساب لا يطابق نوع الدخول المختار" }[
  code] || "حدث خطأ أثناء المصادقة";
}

function setUnsub(unsub) {
  state.unsubs.push(unsub);
}

function clearUnsubs() {
  state.unsubs.forEach(u => u && u());
  state.unsubs = [];
  if (bookingChatUnsub) {
    bookingChatUnsub();
    bookingChatUnsub = null;
  }
  if (adminSupportChatUnsub) {
    adminSupportChatUnsub();
    adminSupportChatUnsub = null;
  }
  if (adminSupportChatUnsub) {
    adminSupportChatUnsub();
    adminSupportChatUnsub = null;
  }
  state.bookingMessages = [];
  realtimeReady = false;
  realtimeUid = null;
}

function h(title, sub = "") {
  return `<header class="header"><div class="brand"><div><h1 class="title">${title}</h1>${sub ? `<p class="sub">${sub}</p>` : ""}</div></div><div class="header-actions">${notificationBell()}</div></header>`;
}


function chatHeader(title) {
  return `<div class="chat-header"><h3>${title}</h3><button class="chat-exit-btn" type="button" data-close-chat="1" aria-label="الخروج من المحادثة">← خروج</button></div>`;
}

function unreadNotificationsCount() {
  if (!state.user) return 0;
  return state.notifications.filter(n => n.toUserId === state.user.uid && !n.isRead).length;
}

function notificationBell() {
  if (!state.user || ["admin", "pending"].includes(state.user.role)) return "";
  const unread = unreadNotificationsCount();
  return `<button class="notif-btn" data-tab="notifications" type="button" aria-label="الإشعارات">🔔${unread ? `<span class="notif-badge">${formatNumber(unread)}</span>` : ""}</button>`;
}

function render() {
  if (!root) return;
  try {
    root.dataset.booted = "1";
    clearInterval(mapCountdownInterval);
    mapCountdownInterval = null;
    if (state.view === "role") renderRole();else
    if (state.view === "auth") renderAuth();else
    if (state.view === "client") renderClient();else
    if (state.view === "outlet") renderOutlet();else
    if (state.view === "pending") renderPending();else
    if (state.view === "admin") renderAdmin();
    root.insertAdjacentHTML("beforeend", renderToast());
  } catch (err) {
    console.error(`${APP_BOOT_LOG} render failed`, err);
  }
}

function renderRole() {
  root.innerHTML = `
    ${h("منفذك", "اختر نوع الدخول")}
    <section class="grid role-grid">
      <article class="card role" data-role="client"><div class="icon">👤</div><h3>عميل</h3></article>
      <article class="card role" data-role="outlet"><div class="icon">🏪</div><h3>منفذ</h3></article>
    </section>
    <section class="grid role-insights">
      <article class="card chart-card">
        <h4>نمو أرباح المنفذ</h4>
        <div class="chart-bars">
          <span style="--h:32%"></span>
          <span style="--h:48%"></span>
          <span style="--h:61%"></span>
          <span style="--h:74%"></span>
          <span style="--h:88%"></span>
        </div>
        <p class="muted">زيادة تصاعدية توضح توسع دخل المنفذ بشكل مستمر.</p>
      </article>
      <article class="card chart-card">
        <h4>الانضمام إلى منافذ متعددة</h4>
        <div class="chart-line">
          <svg viewBox="0 0 320 120" preserveAspectRatio="none">
            <polyline points="0,98 60,82 120,74 180,55 240,40 320,26"></polyline>
          </svg>
        </div>
        <p class="muted">بالتسجيل في التطبيق تنضم إلى شبكة منافذ نشطة داخل البرنامج.</p>
      </article>
      <article class="card chart-card">
        <h4>مؤشر الأمان المالي</h4>
        <div class="security-seal" aria-label="الأمان المالي الكامل">
          <div class="seal-icon">🔐</div>
          <div class="seal-lines"><span></span><span></span><span></span></div>
        </div>
        <p class="muted">حماية وامان عالي لتعاملك المالي</p>
      </article>
    </section>
  `;

  root.querySelectorAll("[data-role]").forEach(el => {
    el.onclick = () => {
      state.role = el.dataset.role;
      state.view = "auth";
      render();
    };
  });

}

function renderAuth() {
  const isClient = state.role === "client";
  const isBusy = loadingCount > 0;
  const authDraft = state.authDraft || {};
  const selectedGovernorate = String(authDraft.governorate || state.user?.governorate || "البصرة");
  root.innerHTML = `
    ${h(isClient ? "حساب العميل" : "حساب المنفذ", "تسجيل دخول أو إنشاء حساب")}
    <section class="card">
        <h3 style="margin-bottom:4px;">إنشاء حساب جديد</h3>
      <p class="muted" style="margin:0 0 10px;">أنشئ حسابك للبدء باستخدام التطبيق</p>
      <form id="authForm">
        <div class="group"><label>الاسم الثلاثي</label><input name="fullName" value="${escapeHtml(authDraft.fullName || "")}" required /></div>
        <div class="group"><label>البريد الإلكتروني</label><input name="email" type="email" value="${escapeHtml(authDraft.email || "")}" placeholder="example@gmail.com" required /></div>
        <div class="group"><label>المحافظة</label><select name="governorate" required>${governorateOptions(selectedGovernorate)}</select></div>
        <div class="group"><label>كلمة السر</label><input type="password" name="password" value="${escapeHtml(authDraft.password || "")}" required /></div>
        ${isClient ? `<div class="warning"><strong>الشروط والأحكام</strong><br>• عمولة السحب لا تتجاوز 0.006 دينار لكل دينار واحد.<br>• الالتزام بالموقع والتحقق قبل تأكيد العملية.<br>• استلام وتسليم الأموال يكون داخل المنفذ حصراً.</div><label class="remember-switch"><input type="checkbox" name="termsAccepted" ${authDraft.termsAccepted ? "checked" : ""} /><span class="switch-ui"></span><span>أوافق على الشروط والأحكام</span></label>` : `<div class="group"><label>اسم المنفذ</label><input name="outletName" value="${escapeHtml(authDraft.outletName || "")}" required /></div><div class="warning"><strong>الشروط والأحكام</strong><br>• عمولة السحب لا تتجاوز 0.006 دينار لكل دينار واحد.<br>• الالتزام بالموقع والتحقق قبل تأكيد العملية.<br>• استلام وتسليم الأموال يكون داخل المنفذ حصراً.<br>• منفذك هو الذي يتحمل استقطاعات البنك أو الشركة.<br>• المنفذ مؤمن بشكل كامل بنظام مراقبة أمن.</div><label class="remember-switch"><input type="checkbox" name="termsAccepted" ${authDraft.termsAccepted ? "checked" : ""} /><span class="switch-ui"></span><span>أوافق على الشروط والأحكام</span></label>`}
        <button class="btn b-orange btn-full" type="submit" ${isBusy ? "disabled" : ""}>تسجيل الدخول</button>
        ${isClient ? `<button class="btn btn-full google-btn-official" type="button" id="googleLoginBtn" ${isBusy ? "disabled" : ""}><span class="google-icon" aria-hidden="true"><svg viewBox="0 0 48 48" width="20" height="20"><path fill="#EA4335" d="M24 9.5c3.54 0 6.74 1.22 9.26 3.61l6.9-6.9C35.98 2.38 30.4 0 24 0 14.62 0 6.51 5.38 2.56 13.22l8.03 6.24C12.52 13.64 17.76 9.5 24 9.5z"/><path fill="#4285F4" d="M46.5 24.5c0-1.56-.14-3.06-.4-4.5H24v9h12.7c-.55 2.96-2.22 5.47-4.73 7.16l7.28 5.64C43.83 37.55 46.5 31.56 46.5 24.5z"/><path fill="#FBBC05" d="M10.59 28.54A14.5 14.5 0 0 1 9.5 24c0-1.58.38-3.08 1.05-4.54l-8.03-6.24A24 24 0 0 0 0 24c0 3.87.93 7.53 2.56 10.78l8.03-6.24z"/><path fill="#34A853" d="M24 48c6.48 0 11.92-2.14 15.89-5.82l-7.28-5.64c-2.02 1.36-4.6 2.16-8.61 2.16-6.24 0-11.48-4.14-13.37-9.96l-8.03 6.24C6.51 42.62 14.62 48 24 48z"/></svg></span><span>تسجيل الدخول باستخدام Google</span></button>` : ""}
        <button class="btn b-gray btn-full" type="button" id="registerBtn" ${isBusy ? "disabled" : ""}>إنشاء حساب جديد</button>
        <button class="btn b-gray btn-full" type="button" id="backBtn" ${isBusy ? "disabled" : ""}>رجوع</button>
      </form>
    </section>
    ${renderLoading()}
  `;

  const form = root.querySelector("#authForm");
  form.querySelectorAll("input, select").forEach(el => el.oninput = el.onchange = () => {
    state.authDraft = {
      ...state.authDraft,
      fullName: String(form.fullName?.value || ""),
      email: String(form.email?.value || ""),
      governorate: String(form.governorate?.value || "البصرة"),
      outletName: String(form.outletName?.value || ""),
      password: String(form.password?.value || ""),
      termsAccepted: !!form.termsAccepted?.checked
    };
  });

  form.onsubmit = async e => {
    e.preventDefault();
    const fd = new FormData(form);
    const fullName = String(fd.get("fullName") || "").trim();
    const email = String(fd.get("email") || "").trim().toLowerCase();
    const governorate = String(fd.get("governorate") || "").trim();
    const outletName = String(fd.get("outletName") || "").trim();
    const password = String(fd.get("password") || "").trim();
    if (!fullName) return showToast("يرجى إدخال الاسم الثلاثي", "warning");
    if (!email) return showToast("أدخل بريدًا إلكترونيًا صحيحًا", "warning");
    if (!governorate) return showToast("يرجى اختيار المحافظة", "warning");
    if (!isClient && !outletName) return showToast("يرجى إدخال اسم المنفذ", "warning");
    if (fd.get("termsAccepted") !== "on") return showToast("يجب الموافقة على الشروط والأحكام لإكمال المتابعة", "warning");
    if (password.length < 6) return showToast("كلمة السر ضعيفة (6 أحرف على الأقل)", "warning");
    if (!spamGuard("login", SPAM_LIMITS.login)) return showToast("تم تجاوز محاولات الدخول، حاول لاحقاً", "warning");
    setLoading(true);
    try {
      await applySelectedPersistence();
      const cred = await signInWithEmailAndPassword(auth, email, password);
      if (email === ADMIN_EMAIL.toLowerCase() && password === ADMIN_PASSWORD) {
        state.user = { uid: "admin", authUid: cred.user.uid, role: "admin", fullName: "مدير النظام", email: cred.user.email || ADMIN_EMAIL };
        state.view = "admin";
        state.tab = "pending";
        setupRealtime();
        render();
        return;
      }
      await ensureUserProfileFromAuth(cred.user, { role: state.role, fullName, governorate, outletName });
      state.authDraft = { fullName: "", email: "", governorate: "البصرة", outletName: "", password: "", termsAccepted: false };
      await handlePostLogin(cred.user.uid, cred.user);
    } catch (err) {
      showToast(authErrorAr(err?.code), "error");
    } finally {
      setLoading(false);
    }
  };

  root.querySelector("#registerBtn").onclick = async () => {
    const fd = new FormData(form);
    const email = String(fd.get("email") || "").trim().toLowerCase();
    const password = String(fd.get("password") || "").trim();
    const fullName = String(fd.get("fullName") || "").trim();
    const outletName = String(fd.get("outletName") || "").trim();
    const governorate = String(fd.get("governorate") || "").trim();
    if (!fullName) return showToast("يرجى إدخال الاسم الثلاثي", "warning");
    if (!email) return showToast("أدخل بريدًا إلكترونيًا صحيحًا", "warning");
    if (looksSuspiciousIdentity(fullName, email)) return showToast("تعذر إنشاء الحساب: يرجى إدخال بيانات حقيقية", "warning");
    if (password.length < 6) return showToast("كلمة السر ضعيفة (6 أحرف على الأقل)", "warning");
    if (!governorate) return showToast("يرجى اختيار المحافظة", "warning");
    if (!isClient && !outletName) return showToast("يرجى إدخال اسم المنفذ", "warning");
    if (fd.get("termsAccepted") !== "on") return showToast("يجب الموافقة على الشروط والأحكام لإكمال التسجيل", "warning");
    if (!spamGuard("register", SPAM_LIMITS.register)) return showToast("تم تجاوز محاولات التسجيل، حاول لاحقاً", "warning");

    setLoading(true);
    try {
      await applySelectedPersistence();
      const cred = await createUserWithEmailAndPassword(auth, email, password);
      await ensureUserProfileFromAuth(cred.user, {
        role: state.role,
        fullName,
        outletName,
        governorate });

      showToast("تم إنشاء الحساب بنجاح", "success");
      state.authDraft = { fullName: "", email: "", governorate: "البصرة", outletName: "", password: "", termsAccepted: false };
      await handlePostLogin(cred.user.uid, cred.user);
    } catch (err) {
      showToast(authErrorAr(err?.code), "error");
    } finally {
      setLoading(false);
    }
  };


  const googleLoginBtn = root.querySelector("#googleLoginBtn");
  if (googleLoginBtn) googleLoginBtn.onclick = async () => {
    const fd = new FormData(form);
    const governorate = String(fd.get("governorate") || "").trim();
    if (!governorate) return showToast("يرجى اختيار المحافظة أولاً قبل تسجيل الدخول عبر Google", "warning");
    if (fd.get("termsAccepted") !== "on") return showToast("يجب الموافقة على الشروط والأحكام قبل تسجيل الدخول عبر Google", "warning");
    setLoading(true);
    try {
      const provider = new GoogleAuthProvider();
      localStorage.setItem("qiqa_pending_role", state.role || "client");
      localStorage.setItem("qiqa_pending_governorate", governorate);
      const cred = await signInWithPopup(auth, provider);
      await ensureUserProfileFromAuth(cred.user, { role: state.role, governorate });
      await handlePostLogin(cred.user.uid, cred.user);
      showToast("تم تسجيل الدخول عبر Google", "success");
    } catch (err) {
      if (["auth/popup-blocked", "auth/popup-closed-by-user", "auth/operation-not-supported-in-this-environment"].includes(err?.code)) {
        try {
          await signInWithRedirect(auth, provider);
          return;
        } catch (redirectErr) {
          showToast(authErrorAr(redirectErr?.code), "error");
        }
      } else {
        showToast(authErrorAr(err?.code), "error");
      }
    } finally {
      setLoading(false);
    }
  };

  root.querySelector("#backBtn").onclick = () => {
    state.view = "role";
    render();
  };
}

async function handlePostLogin(uidValue, authUser = null) {
  const s = await getDoc(doc(db, "users", uidValue));
  if (!s.exists()) return showToast("المستخدم غير موجود");
  const user = s.data();
  const chosenRole = state.role;
  const allowedCross = user.role === "pending" || !chosenRole;
  if (!allowedCross && user.role !== chosenRole) {
    await signOut(auth);
    state.user = null;
    state.view = "auth";
    return showToast(authErrorAr("auth/role-mismatch"), "error");
  }
  state.user = user;
  state.view = user.role === "pending" ? "pending" : user.role;
  state.tab = "requests";
  setupRealtime();
  setupFcm();
  setTimeout(warmupLocationAfterLogin, 200);
  render();
  if (state.user.role === "outlet" && !state.user.outletName) setTimeout(ensureOutletNameAfterLogin, 80);
  if (!state.user.governorate) setTimeout(ensureGovernorateAfterLogin, 60);
}

async function ensureGovernorateAfterLogin() {
  if (!state.user || !state.user.uid || state.user.uid === "admin") return;
  if (state.user.governorate) return;
  const gov = prompt("يرجى إدخال المحافظة لإكمال ملفك", "");
  if (!gov || !gov.trim()) return;
  await updateDoc(doc(db, "users", state.user.uid), { governorate: gov.trim() });
  showToast("تم حفظ المحافظة", "success");
}

async function ensureOutletNameAfterLogin() {
  if (!state.user || state.user.role !== "outlet" || !state.user.uid) return;
  const fallback = String(state.user.fullName || "").trim();
  if (!fallback) return;
  await updateDoc(doc(db, "users", state.user.uid), { outletName: fallback });
}

function setupRealtime() {
  if (!state.user) return;
  if (realtimeReady && realtimeUid === state.user.uid) return;
  clearUnsubs();
  realtimeReady = true;
  realtimeUid = state.user.uid;

  if (state.user.uid === "admin") {
    setUnsub(onSnapshot(collection(db, "users"), snap => {
      state.users = snap.docs.map(d => d.data());
      requestRender();
    }));

    setUnsub(onSnapshot(collection(db, "outletRequests"), snap => {
      state.outletRequests = snap.docs.map(d => d.data());
      requestRender();
    }));

    setUnsub(onSnapshot(collection(db, "bookings"), snap => {
      state.bookings = snap.docs.map(d => ({ bookingDocId: d.id, ...d.data(), bookingId: d.data().bookingId || d.id }));
      processBookingStatusTransitions(state.bookings);
      handleBookingSideEffects();
      requestRender();
    }));
  } else {
    setUnsub(onSnapshot(collection(db, "users"), snap => {
      state.users = snap.docs.map(d => d.data());
      const mine = state.users.find(u => u.uid === state.user.uid);
      if (!mine) return forceSignout();
      state.user = mine;
      if (state.view === "pending" && mine.role === "outlet") {
        state.view = "outlet";
        state.tab = "requests";
      }
      requestRender();
    }));

    if (state.user.role === "client") {
      setUnsub(onSnapshot(query(collection(db, "bookings"), where("clientId", "==", state.user.uid)), snap => {
        state.bookings = snap.docs.map(d => ({ bookingDocId: d.id, ...d.data(), bookingId: d.data().bookingId || d.id }));
        processBookingStatusTransitions(state.bookings);
        handleBookingSideEffects();
        requestRender();
      }));
    } else {
      setUnsub(onSnapshot(collection(db, "bookings"), snap => {
        state.bookings = snap.docs.map(d => ({ bookingDocId: d.id, ...d.data(), bookingId: d.data().bookingId || d.id }));
        processBookingStatusTransitions(state.bookings);
        handleBookingSideEffects();
        requestRender();
      }));
    }
  }

  setUnsub(onSnapshot(collection(db, "ratings"), snap => {
    state.ratings = snap.docs.map(d => d.data());
    requestRender();
  }));

  setUnsub(onSnapshot(query(collection(db, "support_chats"), orderBy("updatedAt", "desc")), snap => {
    state.supportChats = snap.docs.map(d => ({ chatId: d.id, ...d.data() }));
    requestRender();
  }));

  if (state.user.uid === "admin") {
    state.supportMessages = [];
  } else {
    const myChatId = state.user.uid;
    setUnsub(onSnapshot(query(collection(db, "support_chats", myChatId, "messages"), orderBy("createdAt")), snap => {
      state.supportMessages = snap.docs.map(d => ({ messageId: d.id, ...d.data(), chatId: myChatId }));
      requestRender();
      setTimeout(scrollSupportToBottom, 20);
    }));
    setUnsub(onSnapshot(query(collection(db, "notifications"), where("toUserId", "==", state.user.uid), orderBy("createdAt", "desc")), snap => {
      state.notifications = snap.docs.map(d => ({ notificationId: d.id, ...d.data() }));
      requestRender();
    }));
  }

  setUnsub(onSnapshot(collection(db, "rewards"), snap => {
    rewardsCache = snap.docs.map(d => ({ rewardId: d.id, ...d.data() }));
    requestRender();
  }));
}

function forceSignout() {
  signOut(auth).finally(() => {
    clearUnsubs();
    state.user = null;
    state.view = "role";
    showToast("تم حذف الحساب بواسطة المدير");
    render();
  });
}

function renderBottom(tabs) {
  const cls = ["two", "three", "four", "five"][tabs.length - 2] || "three";
  return `<nav class="bottom ${cls}">${tabs.map(t => {const isMap = t.key === "map";const shouldBlink = isMap && state.tab !== "map" && state.bookings.some(b => (b.clientId === state.user?.uid || b.outletId === state.user?.uid || b.createdById === state.user?.uid) && ["accepted", "in_progress"].includes(b.status));return `<button class="tab ${state.tab === t.key ? "active" : ""} ${shouldBlink ? "blink-tab" : ""}" data-tab="${t.key}">${t.label}</button>`;}).join("")}</nav>`;
}

function renderClient() {
  const accepted = state.bookings.find(b => b.clientId === state.user.uid && ["accepted", "in_progress"].includes(b.status));
  const tabs = [{ key: "requests", label: "الطلبات" }, { key: "notifications", label: "الإشعارات" }, { key: "profile", label: "الملف الشخصي" }];
  if (accepted) tabs.push({ key: "map", label: "المنفذ" });

  root.innerHTML = `
    ${h("لوحة العميل", `مرحباً ${state.user.fullName}`)}
    <section class="card points-card"><p class="muted">النقاط: ${formatNumber(state.user.points || 0)}</p><button class="gift-trigger" data-open-modal="rewards" type="button" aria-label="فتح المكافآت">🎁</button></section>
    <section class="card">${clientTabContent(accepted)}</section>
    ${renderBottom(tabs)}
    ${renderModal()}
    ${renderLoading()}
  `;
  bindShared();
  if (state.tab === "map" && accepted) {
    setTimeout(() => drawGoogleMap("mapBox", accepted), 120);
    setTimeout(() => drawGoogleMap("mapBox", accepted), 650);
  }
}

function mapFinancialBox(booking) {
  if (!booking || !state.user) return "";
  const amount = Number(booking.amount || 0);
  const price = Number(booking.price || 0);
  const isAccepter = booking.outletId === state.user.uid;
  const isCharge = booking.type === "deposit";
  let firstLabel = isAccepter ? "استلم" : "سلّم";
  let firstAmount = amount;
  let secondLabel = isAccepter ? "سلّم" : "استلم";
  let secondAmount = Math.max(0, amount - price);

  if (isCharge) {
    if (isAccepter) {
      firstLabel = "استلم";
      firstAmount = amount + price;
      secondLabel = "سلّم";
      secondAmount = amount;
    } else {
      firstLabel = "استلم";
      firstAmount = amount;
      secondLabel = "سلّم";
      secondAmount = amount + price;
    }
  }

  return `<div class="money-box"><h4>ملخص العملية</h4><div class="money-row"><span>${firstLabel}</span><strong>${formatNumber(firstAmount)} دينار عراقي</strong></div><p class="money-words">(${numberToArabicWords(firstAmount)})</p><div class="money-row"><span>${secondLabel}</span><strong>${formatNumber(secondAmount)} دينار عراقي</strong></div><p class="money-words">(${numberToArabicWords(secondAmount)})</p></div>`;
}

function clientTabContent(accepted) {
  if (state.tab === "profile") {
    const mine = state.ratings.filter(r => r.fromUserId === state.user.uid);
    return `
      <h3>الملف الشخصي</h3>
      <p class="muted">الاسم: ${state.user.fullName}</p>
      <p class="muted">البريد: ${state.user.email || "-"}</p>
      <p class="muted">المحافظة: ${escapeHtml(state.user.governorate || "-")}</p>
      <p class="muted">النقاط: ${formatNumber(state.user.points || 0)}</p>
      ${state.user.badgeAssignedByAdmin && (state.user.adminBadgeText || state.user.adminBadge) ? `<div class="badge-box"><span>${escapeHtml(state.user.adminBadgeText || state.user.adminBadge)}</span></div>` : ""}
      <h4 style="margin:8px 0;">ملاحظاتي الخاصة</h4>
      ${mine.map(r => `<div class="item">⭐ ${r.stars} - ${escapeHtml(r.note || "بدون ملاحظة")}</div>`).join("") || '<p class="muted">لا توجد ملاحظات.</p>'}
      <button class="btn b-gray btn-full" data-edit-name="1">تعديل الاسم</button>
      <button class="btn b-blue btn-full" data-open-modal="support-chat">💬 الدعم</button>
      <button class="btn b-danger btn-full" id="logoutBtn">تسجيل خروج</button>
    `;
  }

  if (state.tab === "notifications") {
    return renderNotificationsTab();
  }


  if (state.tab === "map" && accepted) {
    return `
      <h3>تتبع الوصول</h3>
      ${mapFinancialBox(accepted)}
      <article class="item" style="margin-bottom:8px;">
      <p class="muted">اسم المنفذ: ${escapeHtml(state.users.find(u => u.uid === accepted.outletId)?.outletName || state.users.find(u => u.uid === accepted.outletId)?.fullName || "-")}</p>
      <p class="muted">المبلغ: ${formatNumber(accepted.amount)}</p><p class="muted">(${numberToArabicWords(accepted.amount)})</p>
      <p class="muted">السعر: ${formatNumber(accepted.price)}</p><p class="muted">(${numberToArabicWords(accepted.price)})</p>
      <p class="muted">التقييم: ⭐ ${formatNumber(avgRating(accepted.outletId || accepted.clientId))}</p>
      </article>
      <button class="chat-icon-btn ${bookingUnreadCount(accepted) || bookingMessagesCount(accepted) ? "blink-tab has-messages" : ""}" data-open-booking-chat="${accepted.bookingId || accepted.bookingDocId}" type="button" aria-label="مراسلة الطرف الآخر">💬<span class="chat-count">${formatNumber(bookingMessagesCount(accepted))}</span>${bookingUnreadCount(accepted) ? `<span class="notif-badge">${formatNumber(bookingUnreadCount(accepted))}</span>` : ""}</button>
      <button class="btn b-gray btn-full" type="button" data-open-trip-support="${escapeHtml(accepted.bookingId || accepted.bookingDocId || "")}">💬 مراسلة الدعم (دعم الرحلة)</button>
      <button class="btn b-blue btn-full" type="button" data-open-google-maps="${escapeHtml(accepted.bookingId || accepted.bookingDocId || "")}">🗺️ فتح في GOOGLE MAPS</button>
            <div id="mapBox" class="map"></div>
      <div class="warning">يجب الوصول خلال ساعتين و45 دقيقة وإلا سيتم إلغاء الطلب</div>
      <p class="muted">المتبقي: <span class="counter">${remain(accepted.expiresAt?.toMillis?.() || accepted.expiresAt)}</span></p>
      ${accepted.status === "accepted" && isRequester(accepted) ? '<button class="btn b-blue btn-full" data-mark-progress="1">أنا وصلت</button>' : ""}
      ${accepted.status === "in_progress" && isRequester(accepted) ? '<div class="warning">يرجى عدم مشاركة رمز التأكيد إلا بعد استلام المبلغ بالكامل داخل المنفذ. إدخال الرمز يعني إقراراً رسمياً بإتمام العملية.</div><button class="btn b-orange btn-full" data-show-code="1">إظهار الرمز</button>' : ""}
      ${accepted.status === "in_progress" && !isRequester(accepted) ? '<div class="group"><label>رمز التأكيد</label><input id="confirmCodeInput" maxlength="6" /></div><button class="btn b-green btn-full" data-verify-code="1">تأكيد الرمز</button>' : ""}
      ${["accepted", "in_progress"].includes(accepted.status) ? '<button class="btn b-danger btn-full" data-cancel-booking="1">إلغاء الطلب</button><p class="muted">يمكنك إلغاء 3 طلبات يومياً كحد أقصى.</p>' : ""}
    `;
  }

  const shown = myBookings("client", state.user.uid, state.requestFilter);
  return `
    <div class="seg">
      <button data-filter="running" class="${state.requestFilter === "running" ? "active" : ""}">الطلبات الجارية</button>
      <button data-filter="approved" class="${state.requestFilter === "approved" ? "active" : ""}">الطلبات الموافق عليها</button>
      <button data-filter="previous" class="${state.requestFilter === "previous" ? "active" : ""}">الطلبات السابقة</button>
    </div>
    <button class="btn b-blue btn-full" data-open-modal="new-booking">طلب جديد +</button>
    <button class="btn b-gray btn-full" data-open-modal="support-chat">💬 مراسلة الدعم</button>
    <div class="list" style="margin-top:10px;">${shown.map(bookingCard).join("") || (loadingCount ? skeletonList() : '<p class="muted">لا يوجد طلبات.</p>')}</div>
  `;
}

function renderOutlet() {
  const tabs = [
  { key: "requests", label: "الطلبات" },
  { key: "outlets", label: "منافذ" },
  { key: "clients", label: "العملاء" },
  { key: "notifications", label: "الإشعارات" },
  { key: "profile", label: "الملف الشخصي" }];

  const activeBookings = state.bookings.filter(b => ["accepted", "in_progress"].includes(b.status) && (b.outletId === state.user.uid || b.createdById === state.user.uid));
  const selectedBooking = activeBookings.find(b => b.bookingId === state.pending?.mapBookingId || b.bookingDocId === state.pending?.mapBookingId) || null;
  if (activeBookings.length) tabs.push({ key: "map", label: "الخريطة" });

  root.innerHTML = `
    ${h("لوحة المنفذ", `مرحباً ${state.user.outletName || state.user.fullName}`)}
    <section class="card points-card"><p class="muted">النقاط: ${formatNumber(state.user.points || 0)}</p><button class="gift-trigger" data-open-modal="rewards" type="button" aria-label="فتح المكافآت">🎁</button></section>
    <section class="card">${outletTabContent(selectedBooking, activeBookings)}</section>
    ${renderBottom(tabs)}
    ${renderModal()}
    ${renderLoading()}
  `;
  bindShared();
  if (state.tab === "map" && selectedBooking) {
    setTimeout(() => drawGoogleMap("mapBox", selectedBooking), 120);
    setTimeout(() => drawGoogleMap("mapBox", selectedBooking), 650);
  }
}

function outletTabContent(accepted, activeBookings = []) {
  if (state.tab === "profile") {
    const stats = outletStats(state.user.uid);
    return `
      <h3>${state.user.outletName}</h3>
      <p class="muted">البريد: ${state.user.email || "-"}</p>
      <p class="muted">المحافظة: ${escapeHtml(state.user.governorate || "-")}</p>
      <p class="muted">التقييم العام: ${formatNumber(avgRating(state.user.uid))} ⭐</p>
      <p class="muted">عدد العمليات: ${formatNumber(stats.count)}</p>
      <p class="muted">النقاط: ${formatNumber(state.user.points || 0)}</p>
      ${state.user.badgeAssignedByAdmin && (state.user.adminBadgeText || state.user.adminBadge) ? `<div class="badge-box"><span>${escapeHtml(state.user.adminBadgeText || state.user.adminBadge)}</span></div>` : ""}
      <p class="muted">مجموع المبالغ: ${formatNumber(stats.amount)}</p>
      <button class="btn b-gray btn-full" data-edit-name="1">تعديل الاسم</button>
      <button class="btn b-blue btn-full" data-open-modal="support-chat">💬 الدعم</button>
      <button class="btn b-danger btn-full" id="logoutBtn">تسجيل خروج</button>
    `;
  }

  if (state.tab === "notifications") {
    return renderNotificationsTab();
  }

  if (state.tab === "map") {
    if (!activeBookings.length) return '<p class="muted">لا توجد عمليات نشطة على الخريطة.</p>';
    const bookingButtons = activeBookings.map(b => {
      const activeCls = state.pending?.mapBookingId === b.bookingId || state.pending?.mapBookingId === b.bookingDocId ? "active" : "";
      const owner = state.users.find(u => u.uid === b.clientId || u.uid === b.createdById);
      const ownerName = owner?.fullName || owner?.outletName || "-";
      return `<button class="map-booking-card ${activeCls}" data-open-map="${escapeHtml(b.bookingId || b.bookingDocId)}"><strong>عملية #${escapeHtml(String(b.bookingId || b.bookingDocId || "-").slice(-6))}</strong><span>الاسم: ${escapeHtml(ownerName)}</span><span>المبلغ: ${formatNumber(b.amount)} | السعر: ${formatNumber(b.price)}</span></button>`;
    }).join("");
    return `
      <h3>خريطة العملية</h3>
      <div class="map-bookings-list">${bookingButtons}</div>
      ${accepted ? `
      ${accepted.type === "withdraw" ? `<div class="warning">⚠ تنبيه هام:<br>المنفذ يتحمل استقطاعات البنك أو الشركة.</div>` : ""}
      ${mapFinancialBox(accepted)}
      <article class="item" style="margin-bottom:8px;">
      <p class="muted">${accepted.outletId === state.user.uid ? "اسم صاحب الطلب" : "اسم المنفذ"}: ${escapeHtml(accepted.outletId === state.user.uid ?
    state.users.find(u => u.uid === (accepted.clientId || accepted.createdById))?.fullName || state.users.find(u => u.uid === (accepted.clientId || accepted.createdById))?.outletName || "-" :
    state.users.find(u => u.uid === accepted.outletId)?.outletName || state.users.find(u => u.uid === accepted.outletId)?.fullName || "-")}</p>
      <p class="muted">المبلغ: ${formatNumber(accepted.amount)}</p><p class="muted">(${numberToArabicWords(accepted.amount)})</p>
      <p class="muted">السعر: ${formatNumber(accepted.price)}</p><p class="muted">(${numberToArabicWords(accepted.price)})</p>
      <p class="muted">التقييم: ⭐ ${formatNumber(avgRating(accepted.clientId || accepted.outletId))}</p>
      </article>
      <button class="chat-icon-btn ${bookingUnreadCount(accepted) || bookingMessagesCount(accepted) ? "blink-tab has-messages" : ""}" data-open-booking-chat="${accepted.bookingId || accepted.bookingDocId}" type="button" aria-label="مراسلة الطرف الآخر">💬<span class="chat-count">${formatNumber(bookingMessagesCount(accepted))}</span>${bookingUnreadCount(accepted) ? `<span class="notif-badge">${formatNumber(bookingUnreadCount(accepted))}</span>` : ""}</button>
      <button class="btn b-gray btn-full" type="button" data-open-trip-support="${escapeHtml(accepted.bookingId || accepted.bookingDocId || "")}">💬 مراسلة الدعم (دعم الرحلة)</button>
      <button class="btn b-blue btn-full" type="button" data-open-google-maps="${escapeHtml(accepted.bookingId || accepted.bookingDocId || "")}">🗺️ فتح في GOOGLE MAPS</button>
            <button id="refreshMapBtn" class="btn b-blue btn-full" type="button">تحديث الخريطة</button>
      <div id="mapBox" class="map"></div>
      <div class="warning">يجب الوصول خلال ساعتين و45 دقيقة وإلا سيتم إلغاء الطلب</div>
      <p class="muted">المتبقي: <span class="counter">${remain(accepted.expiresAt?.toMillis?.() || accepted.expiresAt)}</span></p>
      ${accepted.status === "accepted" && isRequester(accepted) ? '<button class="btn b-blue btn-full" data-mark-progress="1">أنا وصلت</button>' : ""}
      ${accepted.status === "in_progress" && isRequester(accepted) ? '<div class="warning">يرجى عدم مشاركة رمز التأكيد إلا بعد استلام المبلغ بالكامل داخل المنفذ. إدخال الرمز يعني إقراراً رسمياً بإتمام العملية.</div><button class="btn b-orange btn-full" data-show-code="1">إظهار الرمز</button>' : ""}
      ${accepted.status === "in_progress" && !isRequester(accepted) ? '<div class="group"><label>رمز التأكيد</label><input id="confirmCodeInput" maxlength="6" /></div><button class="btn b-green btn-full" data-verify-code="1">تأكيد الرمز</button>' : ""}
      ${["accepted", "in_progress"].includes(accepted.status) ? '<button class="btn b-danger btn-full" data-cancel-booking="1">إلغاء الطلب</button><p class="muted">يمكنك إلغاء 3 طلبات يومياً كحد أقصى.</p>' : ""}
      ` : '<p class="muted">اختر عملية من القائمة أعلاه.</p>'}
    `;
  }

  if (state.tab === "requests") {
    const shown = myBookings("outlet", state.user.uid, state.requestFilter);
    return `
      <div class="seg">
        <button data-filter="running" class="${state.requestFilter === "running" ? "active" : ""}">الطلبات الجارية</button>
        <button data-filter="approved" class="${state.requestFilter === "approved" ? "active" : ""}">الطلبات الموافق عليها</button>
        <button data-filter="previous" class="${state.requestFilter === "previous" ? "active" : ""}">الطلبات السابقة</button>
      </div>
      <button class="btn b-blue btn-full" data-open-modal="new-booking">طلب جديد +</button>
      <button class="btn b-gray btn-full" data-open-modal="support-chat">💬 مراسلة الدعم</button>
      <div class="list" style="margin-top:10px;">${shown.map(bookingCard).join("") || (loadingCount ? skeletonList() : '<p class="muted">لا يوجد طلبات.</p>')}</div>
    `;
  }

  const isOutlets = state.tab === "outlets";
  const type = state.pending?.type || "withdraw";
  const available = state.bookings.filter(b => {
    if (b.status !== "pending") return false;
    const ownerRole = bookingOwnerRole(b);
    const roleMatch = isOutlets ?
    ownerRole === "outlet" && b.createdById !== state.user.uid :
    ownerRole === "client";
    if (!roleMatch) return false;
    if (type && b.type !== type) return false;

    // must be same governorate; use fallback from request owner profile for legacy bookings
    const outletGov = String(state.user?.governorate || "").trim();
    const bookingGov = bookingGovernorate(b);
    if (outletGov && bookingGov) return outletGov === bookingGov;

    // if one side is missing governorate, keep visible in trial but mark data as needing completion
    return true;
  });

  return `
    <div class="row" style="margin-bottom:8px;">
      <button class="btn ${type === "withdraw" ? "b-orange" : "b-gray"}" data-type="withdraw">سحب</button>
      <button class="btn ${type === "deposit" ? "b-orange" : "b-gray"}" data-type="deposit">شحن</button>
      ${isOutlets ? `<button class="btn ${type === "discharge" ? "b-orange" : "b-gray"}" data-type="discharge">تفريغ</button>` : ""}
    </div>
    <div class="list">${available.map(b => {
    const requester = bookingPartyUser(b, isOutlets ? "outlet" : "client");
    const badge = requester.badgeAssignedByAdmin && (requester.adminBadgeText || requester.adminBadge) ? `<span class="mini-badge">🏅 ${escapeHtml(requester.adminBadgeText || requester.adminBadge)}</span>` : "";
    return `
      <article class="item">
        <span class="badge">${statusAr(b.status)}</span>
        <p><strong>صاحب الطلب</strong></p>
        <p>شارة المستخدم: ${badge || "-"}</p>
        <p>المبلغ: ${formatNumber(b.amount)}</p><p class="muted">(${numberToArabicWords(b.amount)})</p>
        <p>السعر الأصلي: ${formatNumber(b.price)}</p><p class="muted">(${numberToArabicWords(b.price)})</p>
        <p>النوع: ${requestTypeLabel(b.type)}</p>
        <p class="muted">المسافة التقريبية: ${(() => { const km = distanceKm(currentUserLocation, b.clientLocation || b.ownerOutletLocation || b.outletLocation); return `${formatNumber(km)} كم - ${distanceBandLabel(km)}`; })()}</p>
        ${Array.isArray(b.priceProposals) && b.priceProposals.some(p => p.outletId === state.user.uid) ? `<p class="muted" style="color:#16a34a;font-weight:800;">✅ تم اقتراح سعر</p><button class="btn b-gray btn-full" data-ask-accept="${b.bookingId}">تعديل السعر المقترح</button>` : `<button class="btn b-green btn-full" data-ask-accept="${b.bookingId}">إرسال سعر مقترح</button>`}
      </article>
    `;}).join("") || (loadingCount ? skeletonList() : '<p class="muted">لا يوجد طلبات.</p>')}</div>
  `;
}

function renderAdmin() {
  const tabs = [
  { key: "pending", label: "طلبات المنافذ" },
  { key: "outlets", label: "المنافذ" },
  { key: "clients", label: "العملاء" },
  { key: "trips", label: "الرحلات" },
  { key: "support", label: "الدعم" },
  { key: "rewards", label: "المكافآت" }];

  root.innerHTML = `
    ${h("لوحة المدير", "تحديثات فورية عبر Firestore")}
    <section class="card"><button class="btn b-danger btn-full" id="adminLogoutBtn">تسجيل خروج</button></section>
    <section class="card"><p class="muted">إجمالي العمولات: ${formatNumber(financialTotals().commissions)}</p><p class="muted">(${numberToArabicWords(financialTotals().commissions)})</p>${adminContent()}</section>
    ${renderBottom(tabs)}
    ${renderModal()}
    ${renderLoading()}
  `;
  bindShared();
}


function financialTotals() {
  const byOutlet = {};
  const byClient = {};
  let commissions = 0;
  state.bookings.forEach(b => {
    const amount = Number(b.amount || 0);
    if (!amount || b.status !== "completed") return;
    if (b.outletId) byOutlet[b.outletId] = (byOutlet[b.outletId] || 0) + amount;
    if (b.clientId) byClient[b.clientId] = (byClient[b.clientId] || 0) + amount;
    commissions += amount * COMMISSION_RATE;
  });
  return { byOutlet, byClient, commissions };
}


function tsToMs(ts) {
  if (!ts) return 0;
  if (typeof ts === "number") return ts;
  if (typeof ts?.toMillis === "function") return ts.toMillis();
  if (typeof ts?.seconds === "number") return ts.seconds * 1000;
  return 0;
}

function isSupportChatActive(chat) {
  const last = tsToMs(chat?.updatedAt) || Number(chat?.updatedAtMs || 0);
  if (!last) return false;
  return Date.now() - last <= SUPPORT_CHAT_IDLE_MS;
}

function adminContent() {
  if (state.tab === "pending") {
    const pending = state.outletRequests.filter(r => r.status === "pending");
    return pending.length ? `<div class="list">${pending.map(r => `
      <article class="item">
        <h4>${r.outletName}</h4>
        <p class="muted">UID: ${r.uid}</p>
        <div class="row">
          <button class="btn b-green" data-approve="${r.uid}">موافقة</button>
          <button class="btn b-danger" data-reject="${r.uid}">رفض</button>
        </div>
      </article>`).join("")}</div>` : '<p class="muted">لا يوجد طلبات.</p>';
  }

  if (state.tab === "outlets") {
    const outlets = [...state.users.filter(u => u.role === "outlet")].sort((a, b) => Number(b.ratingAverage || 0) - Number(a.ratingAverage || 0));
    return outlets.length ? `<div class="list">${outlets.map(u => {
      const s = outletStats(u.uid);
      const notes = state.ratings.filter(r => r.toUserId === u.uid);
      return `<article class="item">
        <h4>${u.outletName}</h4>
        <p class="muted">الهاتف: ${u.phone || "-"}</p>
        <p class="muted">التقييم: ${formatNumber(avgRating(u.uid))} ⭐</p>
        <p class="muted">عدد العمليات: ${formatNumber(s.count)}</p>
        <p class="muted">مجموع المبالغ: ${formatNumber(s.amount)}</p><p class="muted">(${numberToArabicWords(s.amount)})</p>
        <p class="muted">إجمالي المنفذ (من الحجوزات): ${formatNumber(financialTotals().byOutlet[u.uid] || 0)}</p><p class="muted">(${numberToArabicWords(financialTotals().byOutlet[u.uid] || 0)})</p>
        <p class="muted">العمولة: ${formatNumber(s.amount * COMMISSION_RATE)}</p>
        <p class="muted">إكمال العمليات: ${formatNumber(u.completedCount || 0)}</p>
        <p class="muted">إلغاءات المستخدم: ${formatNumber(u.cancelledByUserCount || 0)}</p>
        <p class="muted">نسبة الإكمال: ${formatNumber(u.completionRate || 0)}%</p>
        <p class="muted">نسبة الإلغاء: ${formatNumber(u.cancellationRate || 0)}%</p>
        <p class="muted">درجة السمعة: ${formatNumber(u.reputationScore || 0)}</p>
        <p class="muted">الشارة الحالية: ${u.badgeAssignedByAdmin && (u.adminBadgeText || u.adminBadge) ? `<span class="badge-box" style="display:inline-flex;"><span>${escapeHtml(u.adminBadgeText || u.adminBadge)}</span></span>` : "-"}</p>
        <details><summary>كل الملاحظات</summary>${notes.map(n => `<div class="muted">⭐${n.stars} - ${escapeHtml(n.note || "بدون ملاحظة")}</div>`).join("") || '<div class="muted">لا يوجد</div>'}</details>
        <div class="row"><button class="btn b-gray" data-set-badge="${u.uid}">تعيين شارة</button><button class="btn b-gray" data-remove-badge="${u.uid}">إزالة الشارة</button><button class="btn b-danger" data-kick-user="${u.uid}">طرد</button></div>
      </article>`;
    }).join("")}</div>` : '<p class="muted">لا يوجد منافذ.</p>';
  }


  if (state.tab === "trips") {
    const tripFilter = state.pending?.adminTripsFilter || "active";
    const tripQuery = String(state.pending?.adminTripQuery || "").trim();
    const activeStatuses = ["pending", "accepted", "in_progress", "awaiting_auto_completion"];
    const list = state.bookings.
    filter(b => tripFilter === "active" ? activeStatuses.includes(b.status) : ["completed", "cancelled", "expired"].includes(b.status)).
    filter(b => {
      if (!tripQuery) return true;
      const bookingCode = String(b.bookingId || b.bookingDocId || "");
      return bookingCode.includes(tripQuery);
    }).
    sort((a, b) => Number(b.createdAt?.seconds || 0) - Number(a.createdAt?.seconds || 0));
    return `
      <div class="seg">
        <button data-admin-trip-filter="active" class="${tripFilter === "active" ? "active" : ""}">الرحلات النشطة</button>
        <button data-admin-trip-filter="previous" class="${tripFilter === "previous" ? "active" : ""}">الرحلات السابقة</button>
        <span></span>
      </div>
      <div class="group"><label>بحث برمز الرحلة</label><input id="adminTripSearchInput" value="${escapeHtml(tripQuery)}" placeholder="اكتب رمز الرحلة" /></div>
      <div class="list">${list.map(b => {
      const client = state.users.find(u => u.uid === (b.clientId || b.createdById));
      const outlet = state.users.find(u => u.uid === b.outletId);
      const clientName = client?.fullName || client?.outletName || "-";
      const outletName = outlet?.outletName || outlet?.fullName || "-";
      return `<article class="item">
          <span class="badge">${statusAr(b.status)}</span>
          <p><strong>رقم العملية:</strong> ${escapeHtml(String(b.bookingId || b.bookingDocId || "-"))}</p>
          <p class="muted">صاحب الطلب: ${escapeHtml(clientName)}</p>
          <p class="muted">المنفذ: ${escapeHtml(outletName)}</p>
          <p class="muted">النوع: ${requestTypeLabel(b.type)}</p>
          <p class="muted">المبلغ: ${formatNumber(b.amount)} | السعر: ${formatNumber(b.price)}</p>
          ${activeStatuses.includes(b.status) ? `<button class="btn b-danger btn-full" data-admin-cancel-booking="${escapeHtml(b.bookingDocId || b.bookingId || "")}">إلغاء الرحلة</button>` : ""}
        </article>`;
    }).join("") || '<p class="muted">لا توجد رحلات.</p>'}</div>
    `;
  }

  if (state.tab === "support") {
    const chats = state.supportChats.filter(c => c.chatId);
    const activeChats = chats.filter(isSupportChatActive);
    const previousChats = chats.filter(c => !isSupportChatActive(c));
    return `<div class="list">
      <article class="item"><button class="btn b-orange btn-full" data-open-modal="broadcast">📢 إشعار عام للجميع</button></article><article class="item"><button class="btn b-blue btn-full" id="adminTestNotificationBtn">🔔 اختبار إشعار بعد 5 ثوانٍ</button><p class="muted">اضغط الزر ثم اخرج من التطبيق لتجربة ظهور الإشعار.</p></article>
      <article class="item"><h4>الدعم النشط</h4>${activeChats.map(c => {
      const u = c.chatId;
      const name = state.users.find(x => x.uid === u)?.fullName || state.users.find(x => x.uid === u)?.outletName || u;
      return `<div class="item" style="margin-top:8px;"><h4>${escapeHtml(name)}</h4><p class="muted">آخر تحديث: ${new Date(tsToMs(c.updatedAt) || Date.now()).toLocaleString("ar-IQ")}</p>${c.source === "trip_support" && c.lastTripId ? `<p class="muted">دعم الرحلة: ${escapeHtml(String(c.lastTripId))}</p>` : ""}<button class="btn b-blue btn-full" data-open-admin-support="${u}">فتح المحادثة</button></div>`;
    }).join("") || '<p class="muted">لا توجد محادثات نشطة.</p>'}</article>
      <article class="item"><h4>المراسلات السابقة</h4>${previousChats.map(c => {
      const u = c.chatId;
      const name = state.users.find(x => x.uid === u)?.fullName || state.users.find(x => x.uid === u)?.outletName || u;
      return `<div class="item" style="margin-top:8px;"><h4>${escapeHtml(name)}</h4><p class="muted">انتهت تلقائياً بعد 10 دقائق من عدم النشاط</p>${c.source === "trip_support" && c.lastTripId ? `<p class="muted">دعم الرحلة: ${escapeHtml(String(c.lastTripId))}</p>` : ""}<button class="btn b-gray btn-full" data-open-admin-support="${u}">عرض المحادثة</button></div>`;
    }).join("") || '<p class="muted">لا توجد مراسلات سابقة.</p>'}</article>
    </div>`;
  }

  if (state.tab === "rewards") {
    return `<div class="list">
      <article class="item">
        <h4>إضافة مكافأة</h4>
        <form id="rewardForm">
          <div class="group"><label>العنوان</label><input name="title" required /></div>
          <div class="group"><label>النقاط المطلوبة</label><input name="pointsRequired" type="number" min="1" required /></div>
          <div class="group"><label>الوصف</label><textarea name="description" required></textarea></div>
          <button class="btn b-green btn-full" type="submit">حفظ المكافأة</button>
        </form>
      </article>
      ${rewardsCache.map(r => `<article class="item"><h4>${escapeHtml(r.title || "")}</h4><p class="muted">${formatNumber(r.pointsRequired || 0)} نقطة</p><p class="muted">${escapeHtml(r.description || "")}</p><p class="muted">الحالة: ${r.active === false ? "معطل" : "نشط"}</p><button class="btn b-gray btn-full" data-toggle-reward="${r.rewardId}">${r.active === false ? "تفعيل" : "تعطيل"}</button></article>`).join("")}
    </div>`;
  }

  const clients = [...state.users.filter(u => u.role === "client")].sort((a, b) => Number(b.ratingAverage || 0) - Number(a.ratingAverage || 0));
  return clients.length ? `<div class="list">${clients.map(u => {
    const ownRatings = state.ratings.filter(r => r.fromUserId === u.uid);
    return `<article class="item">
      <h4>${u.fullName}</h4>
      <p class="muted">الهاتف: ${u.phone || "-"}</p>
      <p class="muted">التقييمات: ${formatNumber(avgByFrom(u.uid))} ⭐</p>
      <p class="muted">إجمالي العميل (من الحجوزات): ${formatNumber(financialTotals().byClient[u.uid] || 0)}</p><p class="muted">(${numberToArabicWords(financialTotals().byClient[u.uid] || 0)})</p>
      <p class="muted">إكمال العمليات: ${formatNumber(u.completedCount || 0)}</p>
      <p class="muted">إلغاءات المستخدم: ${formatNumber(u.cancelledByUserCount || 0)}</p>
      <p class="muted">نسبة الإكمال: ${formatNumber(u.completionRate || 0)}%</p>
      <p class="muted">نسبة الإلغاء: ${formatNumber(u.cancellationRate || 0)}%</p>
      <p class="muted">درجة السمعة: ${formatNumber(u.reputationScore || 0)}</p>
      <p class="muted">الشارة الحالية: ${u.badgeAssignedByAdmin && (u.adminBadgeText || u.adminBadge) ? `<span class="badge-box" style="display:inline-flex;"><span>${escapeHtml(u.adminBadgeText || u.adminBadge)}</span></span>` : "-"}</p>
      <details><summary>ملاحظات العميل</summary>${ownRatings.map(n => `<div class="muted">⭐${n.stars} - ${escapeHtml(n.note || "بدون ملاحظة")}</div>`).join("") || '<div class="muted">لا يوجد</div>'}</details>
      <div class="row"><button class="btn b-gray" data-set-badge="${u.uid}">تعيين شارة</button><button class="btn b-gray" data-remove-badge="${u.uid}">إزالة الشارة</button><button class="btn b-danger" data-kick-user="${u.uid}">طرد</button></div>
    </article>`;
  }).join("")}</div>` : '<p class="muted">لا يوجد عملاء.</p>';
}

function renderModal() {
  if (!state.modal) return "";
  if (state.modal === "new-booking") {
    const bookingDraft = state.bookingDraft || {};
    return `<div class="modal-wrap" data-close="1"><div class="modal" onclick="event.stopPropagation()">
      <h3>طلب جديد</h3>
      <form id="bookingForm">
        <div class="group"><label>نوع الطلب</label><select name="type"><option value="withdraw" ${bookingDraft.type === "withdraw" ? "selected" : ""}>سحب (سحب من بطاقتك)</option><option value="deposit" ${bookingDraft.type === "deposit" ? "selected" : ""}>إيداع (شحن إلى بطاقتك)</option>${state.user?.role === "outlet" ? `<option value="discharge" ${bookingDraft.type === "discharge" ? "selected" : ""}>تفريغ (شحن بطاقة منفذ آخر)</option>` : ""}</select></div><p class="warning" id="withdrawLimitWarn">عمولة السحب لا تتجاوز 0.006 دينار للدينار الواحد.</p>
        <div class="group"><label>المبلغ</label><input name="amount" type="number" min="1" value="${escapeHtml(String(bookingDraft.amount || ""))}" required /></div>
        <p class="muted" id="amountWordsPreview"></p>
        <div class="group"><label>السعر</label><input name="price" type="number" min="1" value="${escapeHtml(String(bookingDraft.price || ""))}" required /></div>
        <p class="muted" id="priceWordsPreview"></p>
        <div class="group"><label>تحديد المصرف</label><input value="مصرف الرافدين" disabled /></div>
        <button class="btn b-orange btn-full" type="submit">إرسال</button>
        <button class="btn b-gray btn-full" data-close="1" type="button">إلغاء</button>
      </form>
    </div></div>`;
  }
  if (state.modal === "confirm-accept") {
    return `<div class="modal-wrap" data-close="1"><div class="modal" onclick="event.stopPropagation()">
      <h3>إرسال سعر مقترح</h3>
      <div class="group"><label>السعر المقترح</label><input id="proposalPriceInput" type="number" min="1" /></div>
      <div class="row"><button class="btn b-green" data-do-accept="1">إرسال</button><button class="btn b-gray" data-close="1">إلغاء</button></div><p class="muted">يمكن لمنفذين فقط إرسال أسعار لكل طلب.
      الحد المسموح: لا أعلى من السعر الأصلي ولا أقل من 20% منه.</p>
    </div></div>`;
  }
  if (state.modal === "rating") {
    return `<div class="modal-wrap" data-close="1"><div class="modal" onclick="event.stopPropagation()">
      <h3>${state.user?.role === "client" ? "تقييم المنفذ" : "تقييم العميل"}</h3>
      <div class="stars">${[1, 2, 3, 4, 5].map(n => `<button class="star ${state.stars >= n ? "active" : ""}" data-star="${n}" type="button">★</button>`).join("")}</div>
      <form id="ratingForm"><div class="group"><label>ملاحظات</label><textarea name="note"></textarea></div><button class="btn b-orange btn-full" type="submit">حفظ</button><button class="btn b-gray btn-full" type="button" data-skip-rating="1">تخطي</button></form>
    </div></div>`;
  }

  if (state.modal === "support-chat") {
    const chatId = state.user.uid;
    const tripId = String(state.pending?.supportTripId || "");
    const msgs = state.supportMessages.filter(m => m.chatId === chatId);
    return `<div class="modal-wrap" data-close="1"><div class="modal modal-full" onclick="event.stopPropagation()">
      ${chatHeader(`الدعم ${tripId ? `- دعم الرحلة #${escapeHtml(tripId)}` : ""}`)}
      <div id="supportMessages" class="chat-list">${msgs.map(m => `<div class="chat-bubble ${m.senderId === state.user.uid ? "mine" : "their"}"><p>${escapeHtml(m.text || "")}</p><small>${new Date(m.createdAt?.seconds ? m.createdAt.seconds * 1000 : Date.now()).toLocaleTimeString("ar-IQ", { hour: "2-digit", minute: "2-digit" })}</small></div>`).join("") || '<p class="muted">ابدأ المحادثة.</p>'}</div>
      <form id="supportForm"><div class="group"><label>الرسالة</label><textarea name="message" required></textarea></div><button class="btn b-orange btn-full" type="submit">إرسال</button></form>
    </div></div>`;
  }
  if (state.modal === "admin-support-chat") {
    const targetId = state.pending?.supportUid;
    const msgs = targetId ? state.supportMessages.filter(m => m.chatId === targetId) : [];
    return `<div class="modal-wrap" data-close="1"><div class="modal modal-full" onclick="event.stopPropagation()">
      ${chatHeader(`محادثة الدعم ${targetId ? `- ${state.users.find(u => u.uid === targetId)?.fullName || state.users.find(u => u.uid === targetId)?.outletName || targetId}` : ""}`)}
      ${!targetId ? '<p class="muted">لم يتم تحديد المحادثة.</p>' : ""}
      <div id="supportMessages" class="chat-list">${msgs.map(m => `<div class="chat-bubble ${(m.senderRole === "admin" || m.senderId === (state.user?.authUid || "admin")) ? "mine" : "their"}"><p>${escapeHtml(m.text || "")}</p><small>${new Date(m.createdAt?.seconds ? m.createdAt.seconds * 1000 : Date.now()).toLocaleTimeString("ar-IQ", { hour: "2-digit", minute: "2-digit" })}</small></div>`).join("") || '<p class="muted">لا توجد رسائل.</p>'}</div>
      <form id="adminSupportForm"><div class="group"><label>الرد</label><textarea name="message" required></textarea></div><button class="btn b-orange btn-full" type="submit">إرسال</button></form>
    </div></div>`;
  }


  if (state.modal === "booking-chat") {
    const msgs = state.bookingMessages || [];
    return `<div class="modal-wrap" data-close="1"><div class="modal modal-full" onclick="event.stopPropagation()">
      ${chatHeader("مراسلة الطرف الآخر")}
      <div id="bookingMessages" class="chat-list">${msgs.map(m => `<div class="chat-bubble ${m.senderId === state.user.uid ? "mine" : "their"}"><p>${escapeHtml(m.text || "")}</p><small>${new Date(m.createdAt?.seconds ? m.createdAt.seconds * 1000 : Date.now()).toLocaleTimeString("ar-IQ", { hour: "2-digit", minute: "2-digit" })}</small></div>`).join("") || '<p class="muted">ابدأ المحادثة.</p>'}</div>
      <form id="bookingChatForm"><div class="group"><label>الرسالة</label><textarea name="message" required></textarea></div><button class="btn b-orange btn-full" type="submit">إرسال</button></form>
    </div></div>`;
  }

  if (state.modal === "in-app-call") {
    const bookingId = String(state.pending?.callBookingId || "");
    return `<div class="modal-wrap" data-close="1"><div class="modal" onclick="event.stopPropagation()">
      <h3>مكالمة صوتية داخل التطبيق</h3>
      <p class="muted">هذه المكالمة تتم داخل البرنامج بدون رقم هاتف.</p>
      <div class="row"><button class="btn b-green" data-send-call-invite="${escapeHtml(bookingId)}">إرسال دعوة المكالمة</button><button class="btn b-gray" data-close="1">إلغاء</button></div>
    </div></div>`;
  }

  if (state.modal === "broadcast") {
    return `<div class="modal-wrap" data-close="1"><div class="modal" onclick="event.stopPropagation()">
      <h3>إرسال إشعار عام</h3>
      <form id="broadcastForm">
        <div class="group"><label>العنوان</label><input name="title" required /></div>
        <div class="group"><label>المحتوى</label><textarea name="body" required></textarea></div>
        <button class="btn b-orange btn-full" type="submit">إرسال للجميع</button>
      </form>
    </div></div>`;
  }
  if (state.modal === "set-admin-badge") {
    const allowed = ["موثوق جداً", "مستخدم جيد", "مستخدم عالي الإلغاء", "منفذ مميز", "عميل مميز"];
    return `<div class="modal-wrap" data-close="1"><div class="modal" onclick="event.stopPropagation()">
      <h3>تعيين شارة</h3>
      <form id="adminBadgeForm">
        <div class="group"><label>الشارة</label><select name="badge">${allowed.map(b => `<option value="${escapeHtml(b)}">${escapeHtml(b)}</option>`).join("")}</select></div>
        <button class="btn b-orange btn-full" type="submit">حفظ</button>
      </form>
      <button class="btn b-gray btn-full" data-close="1">إغلاق</button>
    </div></div>`;
  }

  if (state.modal === "show-token") {
    const code = state.pending?.tokenCode || "------";
    const expiresAt = Number(state.pending?.tokenExpiresAtMs || 0);
    const left = Math.max(0, Math.ceil((expiresAt - Date.now()) / 1000));
    return `<div class="modal-wrap" data-close="1"><div class="modal" onclick="event.stopPropagation()">
      <h3>رمز التأكيد</h3>
      <p class="warning">يرجى عدم مشاركة رمز التأكيد إلا بعد استلام المبلغ بالكامل داخل المنفذ. إدخال الرمز يعني إقراراً رسمياً بإتمام العملية.</p>
      <h2 id="tokenCodeValue" style="text-align:center;letter-spacing:4px;">${code}</h2>
      <p class="muted" style="text-align:center;">الصلاحية المتبقية: <span id="tokenCountdown">${left}</span> ثانية</p>
      <button class="btn b-orange btn-full" data-renew-code="1">تجديد الرمز</button>
      <button class="btn b-gray btn-full" data-close="1">إغلاق</button>
    </div></div>`;
  }
  if (state.modal === "rewards") {
    const activeRewards = rewardsCache.filter(r => r.active !== false);
    return `<div class="modal-wrap" data-close="1"><div class="modal" onclick="event.stopPropagation()">
      <h3>المكافآت</h3>
      <div class="list">${activeRewards.map(r => `<article class="item"><h4>${escapeHtml(r.title || "")}</h4><p class="muted">${formatNumber(r.pointsRequired || 0)} نقطة</p><p class="muted">${escapeHtml(r.description || "")}</p><button class="btn b-orange btn-full" data-redeem-reward="${r.rewardId}">استبدال</button></article>`).join("") || '<p class="muted">لا توجد مكافآت حالياً.</p>'}</div>
    </div></div>`;
  }
  if (state.modal === "buy-points") {
    return `<div class="modal-wrap" data-close="1"><div class="modal" onclick="event.stopPropagation()">
      <h3>شراء نقاط</h3>
      <form id="buyPointsForm">
        <div class="group"><label>الباقة</label><select name="pack"><option value="10:10">10 نقاط = 10$</option><option value="25:20">25 نقطة = 20$</option><option value="50:35">50 نقطة = 35$</option></select></div>
        <p class="muted">سيتم تحويلك إلى Stripe Checkout لإدخال بيانات MasterCard / Visa بشكل آمن.</p>
        <button class="btn b-green btn-full" type="submit">متابعة الدفع</button>
      </form>
    </div></div>`;
  }
  return "";
}

function bindShared() {
  root.querySelectorAll("[data-tab]").forEach(b => b.onclick = () => {state.tab = b.dataset.tab;render();});
  root.querySelectorAll("[data-admin-trip-filter]").forEach(b => b.onclick = () => {state.pending = { ...(state.pending || {}), adminTripsFilter: b.dataset.adminTripFilter };render();});
  const adminTripSearchInput = root.querySelector("#adminTripSearchInput");
  if (adminTripSearchInput) adminTripSearchInput.oninput = e => {
    state.pending = { ...(state.pending || {}), adminTripQuery: String(e.target.value || "") };
    render();
  };
  root.querySelectorAll("[data-filter]").forEach(b => b.onclick = () => {
    clearTimeout(filterDebounceTimer);
    filterDebounceTimer = setTimeout(() => {
      state.requestFilter = b.dataset.filter;
      render();
    }, 120);
  });
  root.querySelectorAll("[data-open-modal]").forEach(b => b.onclick = () => {
    const modalName = b.dataset.openModal;
    if (modalName === "support-chat") state.pending = { ...(state.pending || {}), supportTripId: "" };
    state.modal = modalName;
    render();
  });
  root.querySelectorAll("[data-open-trip-support]").forEach(b => b.onclick = () => {
    state.pending = { ...(state.pending || {}), supportTripId: b.dataset.openTripSupport || "" };
    state.modal = "support-chat";
    render();
  });
  root.querySelectorAll("[data-open-google-maps]").forEach(b => b.onclick = () => openBookingInGoogleMaps(b.dataset.openGoogleMaps));
  root.querySelectorAll("[data-close]").forEach(b => b.onclick = closeModal);
  root.querySelectorAll("[data-type]").forEach(b => b.onclick = () => {state.pending = { ...(state.pending || {}), type: b.dataset.type };render();});

  root.querySelectorAll("[data-open-map]").forEach(b => b.onclick = () => {
    state.pending = { ...(state.pending || {}), mapBookingId: b.dataset.openMap };
    render();
  });

  const bookingForm = root.querySelector("#bookingForm");
  if (bookingForm) {
    bookingForm.onsubmit = createBooking;
    bookingForm.querySelectorAll("input, select").forEach(el => el.oninput = el.onchange = () => {
      state.bookingDraft = {
        type: String(bookingForm.type?.value || "withdraw"),
        amount: String(bookingForm.amount?.value || ""),
        price: String(bookingForm.price?.value || "")
      };
    });
  }
  const amountInput = root.querySelector("#bookingForm input[name='amount']");
  const amountWords = root.querySelector("#amountWordsPreview");
  if (amountInput && amountWords) {
    const priceInput = root.querySelector("#bookingForm input[name='price']");
    const priceWords = root.querySelector("#priceWordsPreview");
    const typeInput = root.querySelector("#bookingForm select[name='type']");
    const withdrawWarn = root.querySelector("#withdrawLimitWarn");
    const renderWords = () => {
      const val = Number(amountInput.value || 0);
      amountWords.textContent = val ? `(${numberToArabicWords(val)})` : "";
      const pVal = Number(priceInput?.value || 0);
      if (priceWords) priceWords.textContent = pVal ? `(${numberToArabicWords(pVal)})` : "";
      if (withdrawWarn) {
        const isWithdraw = (typeInput?.value || "withdraw") === "withdraw";
        withdrawWarn.style.display = isWithdraw ? "block" : "none";
        if (isWithdraw && val > 0 && pVal > val * 0.006) {
          withdrawWarn.textContent = "مرفوض: عمولة السحب تتجاوز 0.006 دينار للدينار الواحد.";
          withdrawWarn.classList.add("warning");
        } else {
          withdrawWarn.textContent = "عمولة السحب لا تتجاوز 0.006 دينار للدينار الواحد.";
        }
      }
    };
    amountInput.oninput = renderWords;
    if (priceInput) priceInput.oninput = renderWords;
    if (typeInput) typeInput.onchange = renderWords;
    renderWords();
  }

  root.querySelectorAll("[data-ask-accept]").forEach(b => b.onclick = () => {
    state.pending = { bookingId: b.dataset.askAccept, ...(state.pending || {}) };
    state.modal = "confirm-accept";
    render();
  });

  const doAccept = root.querySelector("[data-do-accept]");
  if (doAccept) doAccept.onclick = acceptBooking;
  root.querySelectorAll("[data-choose-proposal]").forEach(b => b.onclick = () => choosePriceProposal(b.dataset.chooseProposal, b.dataset.proposalOutlet, b.dataset.proposalPrice));

  const markP = root.querySelector("[data-mark-progress]");
  if (markP) markP.onclick = markInProgress;

  const showCode = root.querySelector("[data-show-code]");
  if (showCode) showCode.onclick = showConfirmationCode;
  const renewCode = root.querySelector("[data-renew-code]");
  if (renewCode) renewCode.onclick = showConfirmationCode;
  const verifyCode = root.querySelector("[data-verify-code]");
  if (verifyCode) verifyCode.onclick = verifyConfirmationCode;

  const refreshMapBtn = root.querySelector("#refreshMapBtn");
  if (refreshMapBtn) refreshMapBtn.onclick = () => {
    const selectedBooking = state.bookings.find(b => b.bookingId === state.pending?.mapBookingId || b.bookingDocId === state.pending?.mapBookingId) ||
    state.bookings.find(b => b.outletId === state.user?.uid && ["accepted", "in_progress"].includes(b.status));
    if (!selectedBooking) return showToast("لا توجد عملية محددة");
    window.mapLoaded = false;
    drawGoogleMap("mapBox", selectedBooking);
  };

  const editNameBtn = root.querySelector("[data-edit-name]");
  if (editNameBtn) editNameBtn.onclick = editName;

  root.querySelectorAll("[data-rate-booking]").forEach(b => b.onclick = () => {
    state.pending = { ...(state.pending || {}), bookingId: b.dataset.rateBooking };
    state.modal = "rating";
    render();
  });

  root.querySelectorAll("[data-open-admin-support]").forEach(b => b.onclick = () => {
    const supportUid = b.dataset.openAdminSupport;
    if (!supportUid) return showToast("تعذر فتح المحادثة");
    if (adminSupportChatUnsub) {
      adminSupportChatUnsub();
      adminSupportChatUnsub = null;
    }
    state.pending = { ...(state.pending || {}), supportUid };
    adminSupportChatUnsub = onSnapshot(query(collection(db, "support_chats", supportUid, "messages"), orderBy("createdAt")), snap => {
      state.supportMessages = snap.docs.map(d => ({ messageId: d.id, ...d.data(), chatId: supportUid }));
      render();
      setTimeout(scrollSupportToBottom, 20);
    });
    state.modal = "admin-support-chat";
    render();
  });

  root.querySelectorAll("[data-open-booking-chat]").forEach(b => b.onclick = () => openBookingChat(b.dataset.openBookingChat));
  root.querySelectorAll("[data-close-chat]").forEach(b => b.onclick = () => closeModal());

  const cancelBookingBtn = root.querySelector("[data-cancel-booking]");
  if (cancelBookingBtn) cancelBookingBtn.onclick = cancelActiveBooking;
  root.querySelectorAll("[data-cancel-pending-booking]").forEach(b => b.onclick = () => cancelPendingBooking(b.dataset.cancelPendingBooking));
  root.querySelectorAll("[data-admin-cancel-booking]").forEach(b => b.onclick = () => adminCancelBooking(b.dataset.adminCancelBooking));

  const supportForm = root.querySelector("#supportForm");
  if (supportForm) supportForm.onsubmit = submitSupportMessage;
  const adminSupportForm = root.querySelector("#adminSupportForm");
  if (adminSupportForm) adminSupportForm.onsubmit = submitAdminSupportMessage;
  const broadcastForm = root.querySelector("#broadcastForm");
  if (broadcastForm) broadcastForm.onsubmit = submitBroadcastNotification;
  const bookingChatForm = root.querySelector("#bookingChatForm");
  if (bookingChatForm) bookingChatForm.onsubmit = submitBookingChatMessage;
  const buyPointsForm = root.querySelector("#buyPointsForm");
  if (buyPointsForm) buyPointsForm.onsubmit = submitBuyPoints;
  const rewardForm = root.querySelector("#rewardForm");
  if (rewardForm) rewardForm.onsubmit = submitReward;
  root.querySelectorAll("[data-toggle-reward]").forEach(b => b.onclick = () => toggleReward(b.dataset.toggleReward));
  root.querySelectorAll("[data-redeem-reward]").forEach(b => b.onclick = () => redeemReward(b.dataset.redeemReward));

  const adminTestNotificationBtn = root.querySelector("#adminTestNotificationBtn");
  if (adminTestNotificationBtn) adminTestNotificationBtn.onclick = scheduleAdminTestNotification;

  const adminLogoutBtn = root.querySelector("#adminLogoutBtn");
  if (adminLogoutBtn) adminLogoutBtn.onclick = () => {
    clearUnsubs();
    state.user = null;
    state.view = "role";
    state.tab = "requests";
    render();
  };

  root.querySelectorAll("[data-star]").forEach(s => s.onclick = () => {state.stars = Number(s.dataset.star);render();});
  const ratingForm = root.querySelector("#ratingForm");
  if (ratingForm) ratingForm.onsubmit = submitRating;
  const skipRatingBtn = root.querySelector("[data-skip-rating]");
  if (skipRatingBtn) skipRatingBtn.onclick = () => closeModal();
  const adminBadgeForm = root.querySelector("#adminBadgeForm");
  if (adminBadgeForm) adminBadgeForm.onsubmit = submitAdminBadge;

  root.querySelectorAll("[data-approve]").forEach(b => b.onclick = () => approveOutlet(b.dataset.approve));
  root.querySelectorAll("[data-reject]").forEach(b => b.onclick = () => rejectOutlet(b.dataset.reject));
  root.querySelectorAll("[data-kick-user]").forEach(b => b.onclick = () => kickUser(b.dataset.kickUser));
  root.querySelectorAll("[data-set-badge]").forEach(b => b.onclick = () => {state.pending = { ...(state.pending || {}), badgeUid: b.dataset.setBadge };state.modal = "set-admin-badge";render();});
  root.querySelectorAll("[data-remove-badge]").forEach(b => b.onclick = () => removeUserBadge(b.dataset.removeBadge));
  root.querySelectorAll("[data-open-notification]").forEach(b => b.onclick = () => openNotification(b.dataset.openNotification));

  const logoutBtn = root.querySelector("#logoutBtn");
  if (logoutBtn) logoutBtn.onclick = async () => {
    await signOut(auth);
    clearUnsubs();
    state.user = null;
    state.view = "role";
    state.tab = "requests";
    render();
  };

  const tokenCountdownEl = root.querySelector("#tokenCountdown");
  if (tokenCountdownEl && state.modal === "show-token") {
    clearInterval(tokenCountdownInterval);
    tokenCountdownInterval = setInterval(() => {
      const left = Math.max(0, Math.ceil((Number(state.pending?.tokenExpiresAtMs || 0) - Date.now()) / 1000));
      const c = root.querySelector("#tokenCountdown");
      const v = root.querySelector("#tokenCodeValue");
      if (c) c.textContent = String(left);
      if (left <= 0) {
        if (v) v.textContent = "------";
        clearInterval(tokenCountdownInterval);
        tokenCountdownInterval = null;
      }
    }, 1000);
  }
}

async function createBooking(e) {
  e.preventDefault();
  if (!state.user || !["client", "outlet"].includes(state.user.role)) return showToast("غير مصرح");
  if (bookingSubmitBusy) return;
  bookingSubmitBusy = true;
  const fd = new FormData(e.target);
  const now = Date.now();
  if (now - lastCreateAt < CREATE_RATE_LIMIT_MS) {
    bookingSubmitBusy = false;
    return showToast("يرجى الانتظار قليلاً قبل إنشاء طلب جديد");
  }
  const type = String(fd.get("type") || "withdraw");
  const amount = Number(fd.get("amount"));
  const price = Number(fd.get("price"));
  if (!Number.isFinite(amount) || amount <= 0 || !Number.isFinite(price) || price <= 0) {
    bookingSubmitBusy = false;
    return showToast("يرجى إدخال مبلغ وسعر صحيحين");
  }
  if (type === "withdraw" && price > amount * 0.006) {
    bookingSubmitBusy = false;
    return showToast("مرفوض: عمولة السحب تتجاوز 0.006 دينار لكل دينار", "error");
  }

  setLoading(true);
  try {
    let mineActive = 0;
    try {
      mineActive = await getOwnedActiveBookingsCount(state.user.uid);
    } catch (err) {
      console.warn(`${APP_BOOT_LOG} owned-active query failed; using local fallback`, err);
      mineActive = state.bookings.filter(b => b.clientId === state.user.uid && ["pending", "accepted", "in_progress"].includes(b.status)).length;
    }

    const ownerLimit = state.user.role === "client" ? 1 : 2;
    if (mineActive >= ownerLimit) return showToast(state.user.role === "client" ? "لديك طلب نشط بالفعل" : "لا يمكنك إنشاء أكثر من طلبين نشطين");

    let acceptedActive = 0;
    try {
      acceptedActive = await getAcceptedActiveBookingsCount(state.user.uid);
    } catch (err) {
      console.warn(`${APP_BOOT_LOG} accepted-active query failed; using local fallback`, err);
      acceptedActive = state.bookings.filter(b => b.outletId === state.user.uid && ["accepted", "in_progress"].includes(b.status)).length;
    }
    if (acceptedActive > 0) return showToast("لا يمكنك إنشاء طلب جديد وأنت حالياً منفذ لطلب آخر");

    const location = await requireLocationForAction("create-booking");
    const safeLocation = location && Number.isFinite(Number(location.lat)) && Number.isFinite(Number(location.lng)) ? location : null;
    if (!safeLocation) {
      console.warn(`${APP_BOOT_LOG} create-booking without live location (WebView-safe fallback)`, {
        uid: state.user.uid,
        hasProfileLocation: !!(state.user?.location && Number.isFinite(Number(state.user.location.lat)) && Number.isFinite(Number(state.user.location.lng)))
      });
      showToast("تعذر قراءة موقعك الحالي الآن، سيتم إنشاء الطلب بدون موقع لحظي", "warning");
    }

    await addDoc(collection(db, "bookings"), {
      bookingId: uid(),
      createdById: state.user.uid,
      requestOwnerRole: state.user.role,
      type,
      amount,
      price,
      clientId: state.user.uid,
      outletId: null,
      status: "pending", // FIX: never auto-accept
      clientLocation: safeLocation,
      outletLocation: state.user.role === "outlet" ? safeLocation : null,
      ownerOutletLocation: state.user.role === "outlet" ? safeLocation : null,
      governorate: state.user.governorate || "",
      bankName: "مصرف الرافدين",
      createdAt: serverTimestamp(),
      expiresAt: Date.now() + EXPIRY_MS,
      unreadForClient: 0,
      unreadForOutlet: 0,
      chatMessagesCount: 0 });

    lastCreateAt = Date.now();
    await logAction("create_booking", state.user.uid, { role: state.user.role });
    state.bookingDraft = { type: "withdraw", amount: "", price: "" };
    closeModal();
    showToast("تم إنشاء الطلب بنجاح");
  } catch (err) {
    console.error(`${APP_BOOT_LOG} createBooking failed`, err);
    if (err?.code === "permission-denied") {
      showToast("تعذر إنشاء الطلب بسبب صلاحيات قاعدة البيانات. تحقق من قواعد Firestore.", "error");
    } else if (err?.code === "unavailable" || err?.code === "network-request-failed") {
      showToast("تعذر إنشاء الطلب بسبب مشكلة اتصال. حاول مرة أخرى.", "error");
    } else {
      showToast("تعذر إنشاء الطلب حالياً، حاول مرة أخرى", "error");
    }
  } finally {
    bookingSubmitBusy = false;
    setLoading(false);
  }
}

async function acceptBooking() {
  if (!state.user || state.user.role !== "outlet") return showToast("غير مصرح");
  const b = state.bookings.find(x => x.bookingId === state.pending?.bookingId || x.bookingDocId === state.pending?.bookingId);
  const id = state.pending?.bookingId;
  if (!id || !b?.bookingDocId) return;
  const proposalPrice = Number(root.querySelector("#proposalPriceInput")?.value || 0);
  if (!Number.isFinite(proposalPrice) || proposalPrice <= 0) return showToast("يرجى إدخال سعر مقترح صحيح", "warning");
  if (!spamGuard("proposal", SPAM_LIMITS.proposal)) return showToast("تم تجاوز حد إرسال المقترحات مؤقتاً", "warning");
  const originalPrice = Number(b.price || 0);
  const minAllowed = originalPrice * 0.8;
  if (proposalPrice > originalPrice) return showToast("لا يمكن أن يكون السعر المقترح أعلى من السعر الأصلي", "warning");
  if (proposalPrice < minAllowed) return showToast("لا يمكن أن يكون السعر المقترح أقل من 80% من السعر الأصلي", "warning");
  const outletGov = String(state.user.governorate || "").trim();
  const reqGov = bookingGovernorate(b);
  if (outletGov && reqGov && outletGov !== reqGov) return showToast("لا يمكن تقديم سعر إلا لنفس المحافظة", "warning");

  setLoading(true);
  try {
    const ref = doc(db, "bookings", b.bookingDocId);
    const snap = await getDoc(ref);
    if (!snap.exists()) throw new Error("not_found");
    const data = snap.data();
    if (data.status !== "pending") throw new Error("already_handled");
    const proposals = Array.isArray(data.priceProposals) ? data.priceProposals : [];
    const mine = proposals.find(p => p.outletId === state.user.uid);
    if (!mine && proposals.length >= 2) return showToast("تم الوصول إلى الحد الأقصى للمنافذ المقترحة (2)", "warning");
    const outletLocation = await requireLocationForAction("accept-booking");
    if (!outletLocation) return;
    const next = mine ? proposals.map(p => p.outletId === state.user.uid ? { ...p, price: proposalPrice, createdAtMs: Date.now(), outletLocation: outletLocation || p.outletLocation || null } : p) : [...proposals, { outletId: state.user.uid, price: proposalPrice, createdAtMs: Date.now(), outletLocation: outletLocation || null }];
    await updateDoc(ref, { priceProposals: next, lastProposalAt: serverTimestamp() });
    await logAction("proposal_price", state.user.uid, { bookingId: id, proposalPrice });
    const ownerId = data.clientId || data.createdById;
    console.info(`${APP_BOOT_LOG} proposal push target resolved`, {
      bookingId: data.bookingId || id,
      ownerId,
      clientId: data.clientId || "",
      createdById: data.createdById || ""
    });
    if (ownerId) {
      await addNotification(ownerId, "price_proposal", data.bookingId || id, "تم اقتراح سعر 💰", "تم إرسال عرض سعر لطلبك");
      await sendPushNotification(ownerId, "تم اقتراح سعر 💰", "تم إرسال عرض سعر لطلبك", data.bookingId || id);
    }
    showToast("تم إرسال السعر المقترح", "success");
    closeModal();
  } finally {
    setLoading(false);
  }
}

async function choosePriceProposal(bookingKey = "", outletId = "", proposalPrice = "") {
  if (!state.user?.uid) return showToast("غير مصرح");
  const current = state.bookings.find(b => (b.bookingDocId === bookingKey || b.bookingId === bookingKey));
  if (!current?.bookingDocId || current.status !== "pending") return showToast("لا يمكن اختيار منفذ لهذا الطلب", "warning");
  if (!(current.clientId === state.user.uid || current.createdById === state.user.uid)) return showToast("هذا الخيار لصاحب الطلب فقط");
  if (!outletId) return showToast("تعذر اختيار المنفذ", "warning");
  setLoading(true);
  try {
    const location = await requireLocationForAction("create-booking");
    if (!location) return;
    await updateDoc(doc(db, "bookings", current.bookingDocId), {
      outletId,
      status: "accepted",
      price: Number(proposalPrice || current.price || 0),
      outletLocation: location,
      accepterOutletLocation: location,
      expiresAt: Date.now() + EXPIRY_MS,
      acceptedAt: serverTimestamp() });
    await logAction("choose_proposal", state.user.uid, { bookingId: current.bookingId || current.bookingDocId, outletId, price: Number(proposalPrice || 0) });
    await notifyBookingParties({ ...current, outletId }, "booking_accepted", "تم قبول الطلب", "تم اختيار المنفذ والبدء بالرحلة");
    console.info(`${APP_BOOT_LOG} proposal accepted push target resolved`, {
      bookingId: current.bookingId || current.bookingDocId || "",
      outletId
    });
    if (outletId) {
      await addNotification(outletId, "proposal_accepted", current.bookingId || current.bookingDocId || "", "تم قبول عرضك ✅", "تم قبول عرض السعر الخاص بك");
      await sendPushNotification(outletId, "تم قبول عرضك ✅", "تم قبول عرض السعر الخاص بك", current.bookingId || current.bookingDocId || "");
    }
    showToast("تم اختيار المنفذ وبدء الطلب", "success");
  } finally {
    setLoading(false);
  }
}

async function markInProgress() {
  const current = activeBooking();
  if (!current) return;
  if (!isRequester(current)) return showToast("هذا الزر لصاحب الطلب فقط");
  const p1 = current.clientLocation || current.outletLocation;
  const p2 = current.outletLocation || current.clientLocation;
  const meters = distanceKm(p1, p2) * 1000;
  if (meters > 100) return showToast("يجب أن تكون المسافة أقل من 100 متر");
  if (!current.bookingDocId) return;
  await updateDoc(doc(db, "bookings", current.bookingDocId), { status: "in_progress", arrivedAt: Date.now() });
  await notifyBookingParties(current, "booking_in_progress", "وصل العميل إلى الموقع", "العميل وصل إلى موقع العملية");
  await logAction("in_progress", state.user.uid, { bookingId: current.bookingId });
}

async function showConfirmationCode() {
  const current = activeBooking();
  if (!current) return;
  if (!isRequester(current)) return;
  const meters = distanceKm(current.clientLocation, current.outletLocation) * 1000;
  if (meters > 100) return showToast("يجب أن تكون المسافة أقل من 100 متر قبل إظهار الرمز");
  if (!current.bookingDocId) return;
  setLoading(true);
  try {
    const code = String(Math.floor(100000 + Math.random() * 900000));
    const tokenHash = await hashToken(code);
    const tokenExpiresAtMs = Date.now() + 20 * 1000;
    await updateDoc(doc(db, "bookings", current.bookingDocId), {
      tokenHash,
      tokenExpiresAtMs,
      tokenUsed: false,
      tokenIssuedAt: serverTimestamp(),
      tokenTTLSeconds: 20 });

    state.pending = { ...(state.pending || {}), tokenCode: code, tokenExpiresAtMs, bookingId: current.bookingId };
    state.modal = "show-token";
    render();
  } finally {
    setLoading(false);
  }
}

async function verifyConfirmationCode() {
  const current = activeBooking();
  if (!current) return;
  if (current.status !== "in_progress") return showToast("الحالة غير صالحة للتحقق");
  if (isRequester(current)) return;
  if (!current.bookingDocId) return;
  setLoading(true);
  try {
    const input = document.getElementById("confirmCodeInput");
    const code = String(input?.value || "").trim();
    if (!code) return showToast("أدخل الرمز");
    if (Date.now() > Number(current.tokenExpiresAtMs || 0)) return showToast("انتهت صلاحية الرمز");
    if (current.tokenUsed) return showToast("تم استخدام الرمز مسبقاً");
    const fresh = await getDoc(doc(db, "bookings", current.bookingDocId));
    if (!fresh.exists()) return;
    const freshData = fresh.data();
    if (freshData.status !== "in_progress") return showToast("الحالة غير صالحة للتحقق");
    if (Date.now() > Number(freshData.tokenExpiresAtMs || 0)) return showToast("انتهت صلاحية الرمز");
    if (freshData.tokenUsed) return showToast("تم استخدام الرمز مسبقاً");
    const tokenHash = await hashToken(code);
    if (tokenHash !== String(freshData.tokenHash || "")) return showToast("الرمز غير صحيح");
    await updateDoc(doc(db, "bookings", current.bookingDocId), {
      status: "completed",
      tokenUsed: true,
      completionPromptAtMs: Date.now() });

    setTimeout(() => {
      handleBookingSideEffects();
    }, 300);
    if (freshData.clientId) await updateDoc(doc(db, "users", freshData.clientId), { points: increment(1) });
    if (freshData.outletId) await updateDoc(doc(db, "users", freshData.outletId), { points: increment(1) });
    await recalculateBookingParticipantsReputation(freshData);
    await logAction("complete_booking", state.user.uid, { bookingId: current.bookingId });
    const target = ratingTargetUserId(current);
    if (target) {
      await addNotification(target, "booking_completed", current.bookingId, "اكتملت العملية", "تم إكمال العملية بنجاح");
      await sendPushNotification(target, "اكتملت العملية", "تم إكمال العملية بنجاح", current.bookingId);
    }
    if (!state.ratings.find(r => r.bookingId === current.bookingId && r.fromUserId === state.user.uid) && target) {
      state.pending = { targetUserId: target, bookingId: current.bookingId };
      state.modal = "rating";
      render();
    }
  } finally {
    setLoading(false);
  }
}

function countRecentCancellations(uidValue) {
  const cutoffMs = Date.now() - 24 * 60 * 60 * 1000;
  return state.bookings.filter(b => b.cancelledBy === uidValue && b.status === "cancelled" && tsToMs(b.cancelledAt) >= cutoffMs).length;
}


async function cancelPendingBooking(bookingKey = "") {
  if (!state.user?.uid) return showToast("غير مصرح");
  const current = state.bookings.find(b => (b.bookingDocId === bookingKey || b.bookingId === bookingKey) && b.status === "pending");
  if (!current?.bookingDocId) return showToast("لا يمكن إلغاء الطلب بعد الآن", "warning");
  if (!(current.clientId === state.user.uid || current.createdById === state.user.uid)) return showToast("هذا الزر لصاحب الطلب فقط");
  setLoading(true);
  try {
    await updateDoc(doc(db, "bookings", current.bookingDocId), { status: "cancelled", cancelledBy: state.user.uid, cancelledAt: serverTimestamp() });
    await logAction("cancel_pending_by_requester", state.user.uid, { bookingId: current.bookingId || current.bookingDocId });
    showToast("تم إلغاء الطلب قبل قبوله", "warning");
  } finally {
    setLoading(false);
  }
}

async function cancelActiveBooking() {
  if (mapCancelBusy) return;
  const current = activeBooking();
  if (!current?.bookingDocId) return;
  if (!(current.clientId === state.user?.uid || current.outletId === state.user?.uid || current.createdById === state.user?.uid)) return showToast("غير مصرح بإلغاء هذا الطلب");
  const usedInLast24h = countRecentCancellations(state.user.uid);
  if (usedInLast24h >= 3) return showToast("وصلت للحد الأقصى لإلغاء الطلبات (3 خلال 24 ساعة)");
  mapCancelBusy = true;
  setLoading(true);
  try {
    await updateDoc(doc(db, "bookings", current.bookingDocId), { status: "cancelled", cancelledBy: state.user.uid, cancelledAt: serverTimestamp() });
    const cancelAtMs = Date.now();
    await recalculateBookingParticipantsReputation(current);
    await logAction("cancel_by_user", state.user.uid, { bookingId: current.bookingId, cancelAtMs });
    await notifyBookingParties(current, "booking_cancelled", "تم إلغاء الطلب", "تم إلغاء الطلب من أحد الأطراف");
    showToast("تم إلغاء الطلب", "warning");
  } finally {
    mapCancelBusy = false;
    setLoading(false);
  }
}

async function adminCancelBooking(bookingDocOrId) {
  if (state.user?.uid !== "admin") return;
  const b = state.bookings.find(x => x.bookingDocId === bookingDocOrId || x.bookingId === bookingDocOrId);
  if (!b?.bookingDocId) return showToast("لم يتم العثور على الرحلة", "error");
  await updateDoc(doc(db, "bookings", b.bookingDocId), { status: "cancelled", cancelledBy: "admin", cancelledAt: serverTimestamp() });
  await logAction("admin_cancel_booking", "admin", { bookingId: b.bookingId || b.bookingDocId });
  if (b.clientId) await addNotification(b.clientId, "booking_cancelled", b.bookingId || b.bookingDocId, "تم إلغاء الرحلة من الإدارة", "تم إلغاء الرحلة من قبل الإدارة");
  if (b.outletId) await addNotification(b.outletId, "booking_cancelled", b.bookingId || b.bookingDocId, "تم إلغاء الرحلة من الإدارة", "تم إلغاء الرحلة من قبل الإدارة");
  showToast("تم إلغاء الرحلة", "warning");
}

async function submitRating(e) {
  e.preventDefault();
  if (!state.stars) return showToast("اختر تقييم");
  const booking = state.bookings.find(b => b.bookingId === state.pending?.bookingId || b.bookingDocId === state.pending?.bookingId);
  if (!booking) return;
  const note = String(new FormData(e.target).get("note") || "").trim();
  const toUserId = state.pending?.targetUserId || ratingTargetUserId(booking);
  if (!toUserId) return showToast("لا يمكن تحديد الطرف الآخر");
  await addDoc(collection(db, "ratings"), {
    bookingId: booking.bookingId,
    fromUserId: state.user.uid,
    toUserId,
    stars: state.stars,
    note,
    createdAt: serverTimestamp() });

  await logAction("rate_booking", state.user.uid, { bookingId: booking.bookingId, stars: state.stars });
  closeModal();
}

async function approveOutlet(uidValue) {
  if (state.user?.uid !== "admin") return;
  await updateDoc(doc(db, "outletRequests", uidValue), { status: "approved" });
  await updateDoc(doc(db, "users", uidValue), { role: "outlet", location: outletSeedPoints[Math.floor(Math.random() * outletSeedPoints.length)] });
  await sendPushNotification(uidValue, "تم قبول تسجيل منفذك 🎉", "تم قبول تسجيل منفذك 🎉", null);
  await logAction("approve_outlet", "admin", { uid: uidValue });
}

async function rejectOutlet(uidValue) {
  if (state.user?.uid !== "admin") return;
  await updateDoc(doc(db, "outletRequests", uidValue), { status: "rejected" });
  await logAction("reject_outlet", "admin", { uid: uidValue });
}

async function kickUser(uidValue) {
  if (state.user?.uid !== "admin") return;
  if (uidValue === state.user?.uid) return showToast("لا يمكن حذف نفسك");
  await deleteDoc(doc(db, "users", uidValue)); // instant realtime remove
  await logAction("kick_user", "admin", { uid: uidValue });
}

async function submitAdminBadge(e) {
  e.preventDefault();
  if (state.user?.uid !== "admin") return;
  const uidValue = state.pending?.badgeUid;
  if (!uidValue) return;
  const badgeText = String(new FormData(e.target).get("badge") || "").trim();
  const allowed = ["موثوق جداً", "مستخدم جيد", "مستخدم عالي الإلغاء", "منفذ مميز", "عميل مميز"];
  if (!allowed.includes(badgeText)) return showToast("شارة غير صالحة", "error");
  await updateDoc(doc(db, "users", uidValue), {
    adminBadge: badgeText,
    adminBadgeText: badgeText,
    adminBadgeIcon: "",
    badgeAssignedByAdmin: true,
    badgeAssignedAt: serverTimestamp() });

  showToast("تم تعيين الشارة", "success");
  closeModal();
}

async function removeUserBadge(uidValue) {
  if (state.user?.uid !== "admin") return;
  await updateDoc(doc(db, "users", uidValue), {
    adminBadge: "",
    adminBadgeText: "",
    adminBadgeIcon: "",
    badgeAssignedByAdmin: false,
    badgeAssignedAt: null });

  showToast("تمت إزالة الشارة", "info");
}


async function recalculateUserReputation(uidValue) {
  if (!uidValue || uidValue === "admin") return;
  const byClient = await getDocs(query(collection(db, "bookings"), where("clientId", "==", uidValue)));
  const byOutlet = await getDocs(query(collection(db, "bookings"), where("outletId", "==", uidValue)));
  const map = new Map();
  byClient.docs.forEach(d => map.set(d.id, d.data()));
  byOutlet.docs.forEach(d => map.set(d.id, d.data()));
  const rows = [...map.values()];
  const completedCount = rows.filter(b => b.status === "completed").length;
  const cancelledByUserCount = rows.filter(b => b.status === "cancelled" && b.cancelledBy === uidValue).length;
  const cancelledByOtherCount = rows.filter(b => b.status === "cancelled" && b.cancelledBy && b.cancelledBy !== uidValue).length;
  const totalAcceptedCount = rows.filter(b => b.outletId && b.status !== "pending").length;
  const completionRate = totalAcceptedCount ? Number((completedCount / totalAcceptedCount * 100).toFixed(2)) : 0;
  const cancellationRate = totalAcceptedCount ? Number((cancelledByUserCount / totalAcceptedCount * 100).toFixed(2)) : 0;
  const reputationScore = Number((completionRate - cancellationRate).toFixed(2));
  await updateDoc(doc(db, "users", uidValue), {
    completedCount,
    cancelledByUserCount,
    cancelledByOtherCount,
    totalAcceptedCount,
    completionRate,
    cancellationRate,
    reputationScore });

}

async function recalculateBookingParticipantsReputation(booking) {
  if (!booking) return;
  const ids = [booking.clientId, booking.outletId, booking.createdById].filter(Boolean);
  for (const id of [...new Set(ids)]) {
    await recalculateUserReputation(id);
  }
}

async function logAction(actionType, userId, details = {}) {
  await addDoc(collection(db, "logs"), { actionType, userId, details, timestamp: serverTimestamp() });
}

function closeModal() {
  clearInterval(tokenCountdownInterval);
  tokenCountdownInterval = null;
  if (bookingChatUnsub) {
    bookingChatUnsub();
    bookingChatUnsub = null;
  }
  if (adminSupportChatUnsub) {
    adminSupportChatUnsub();
    adminSupportChatUnsub = null;
  }
  state.bookingMessages = [];
  state.modal = null;
  state.stars = 0;
  state.pending = null;
  render();
}

function bookingPartyUser(booking, preferred = "client") {
  if (!booking) return {};
  const ids = preferred === "outlet" ? [booking.outletId, booking.clientId, booking.createdById] : [booking.clientId, booking.createdById, booking.outletId];
  for (const id of ids) {
    if (!id) continue;
    const user = state.users.find(u => u.uid === id);
    if (user) return user;
  }
  return {};
}

function bookingUnreadCount(booking) {
  if (!booking || !state.user) return 0;
  if (state.user.uid === booking.clientId) return Number(booking.unreadForClient || 0);
  if (state.user.uid === booking.outletId) return Number(booking.unreadForOutlet || 0);
  return 0;
}

function bookingMessagesCount(booking) {
  if (!booking) return 0;
  return Number(booking.chatMessagesCount || 0);
}

function bookingOwnerRole(b) {
  if (!b) return "client";
  if (b.requestOwnerRole === "client" || b.requestOwnerRole === "outlet") return b.requestOwnerRole;
  const owner = state.users.find(u => u.uid === b.createdById);
  if (owner?.role === "outlet") return "outlet";
  return "client";
}

function bookingGovernorate(b) {
  if (!b) return "";
  const direct = String(b.governorate || "").trim();
  if (direct) return direct;
  const ownerId = b.clientId || b.createdById;
  const owner = state.users.find(u => u.uid === ownerId);
  return String(owner?.governorate || "").trim();
}

function renderPriceProposals(booking) {
  const list = Array.isArray(booking?.priceProposals) ? booking.priceProposals : [];
  if (!list.length) return '<p class="muted">لا توجد أسعار مقترحة بعد.</p>';
  const usersById = new Map(state.users.map(u => [u.uid, u]));
  const revealNames = booking.status === "accepted";
  return `<div class="list" style="margin:8px 0;">${list.map(p => {
    const u = usersById.get(p.outletId) || {};
    const name = u.outletName || u.fullName || 'منفذ';
    const badge = u.badgeAssignedByAdmin && (u.adminBadgeText || u.adminBadge) ? `<span class="mini-badge">🏅 ${escapeHtml(u.adminBadgeText || u.adminBadge)}</span>` : "-";
    const chosen = booking.outletId && booking.outletId === p.outletId && booking.status === 'accepted';
    return `<article class="item">${revealNames ? `<p><strong>${escapeHtml(name)}</strong></p>` : `<p><strong>منفذ مقترِح</strong></p>`}<p>الشارة: ${badge}</p><p>السعر المقترح: ${formatNumber(p.price || 0)}</p><p class="muted">${(() => { const km = distanceKm(currentUserLocation, p.outletLocation || booking.outletLocation || booking.clientLocation); return `المسافة: ${formatNumber(km)} كم - ${distanceBandLabel(km)}`; })()}</p>${booking.status === 'pending' ? `<button class="btn b-green btn-full" data-choose-proposal="${escapeHtml(booking.bookingDocId || booking.bookingId || '')}" data-proposal-outlet="${escapeHtml(p.outletId || '')}" data-proposal-price="${escapeHtml(String(p.price || ''))}">اختيار هذا المنفذ</button>` : (chosen ? '<p class="muted">تم اختيار هذا المنفذ</p>' : '')}</article>`;
  }).join('')}</div>`;
}

function bookingCard(b) {
  const canRate = state.user && b.status === "completed" && !state.ratings.find(r => r.bookingId === b.bookingId && r.fromUserId === state.user.uid) && ratingTargetUserId(b);
  const isClientView = state.user?.uid === b.clientId;
  const peer = isClientView ?
  b.outletId ? state.users.find(u => u.uid === b.outletId) : null :
  state.users.find(u => u.uid === (b.clientId || b.createdById));
  const peerName = peer?.fullName || peer?.outletName || "-";
  const stars = formatNumber(peer?.ratingAverage || avgByFrom(peer?.uid || b.clientId) || 0);
  const badge = peer?.badgeAssignedByAdmin && (peer.adminBadgeText || peer.adminBadge) ? `<span class="mini-badge">🏅 ${escapeHtml(peer.adminBadgeText || peer.adminBadge)}</span>` : "";
  const revealPeerIdentity = b.status !== "pending";
  const peerLine = !isClientView && peer && revealPeerIdentity ?
  `<p><strong>صاحب الطلب: ${escapeHtml(peerName)}</strong> ⭐ ${stars} ${badge}</p>` :
  (!isClientView && !revealPeerIdentity ? `<p class="muted">صاحب الطلب: مخفي حتى قبول الطلب ${badge || ""}</p>` : "");
  return `<article class="item">
    <span class="badge">${statusAr(b.status)}</span>
    ${peerLine}
    <p>النوع: ${requestTypeLabel(b.type)}</p>
    <p>المبلغ: ${formatNumber(b.amount)}</p><p class="muted">(${numberToArabicWords(b.amount)})</p>
    <p>السعر: ${formatNumber(b.price)}</p><p class="muted">(${numberToArabicWords(b.price)})</p>
    ${["completed", "cancelled", "expired"].includes(b.status) ? `<p class="muted">تاريخ الطلب: ${formatBookingDate(b.createdAt)}</p><p class="muted">رمز العملية: ${escapeHtml(String(b.bookingId || b.bookingDocId || "-"))}</p>` : ""}
    ${(b.status === "pending" && (b.clientId === state.user?.uid || b.createdById === state.user?.uid)) ? renderPriceProposals(b) : ""}
    ${b.status === "pending" && isClientView ? `<button class="btn b-danger btn-full" data-cancel-pending-booking="${escapeHtml(b.bookingDocId || b.bookingId || "")}">إلغاء الطلب</button><p class="muted">يمكنك الإلغاء بحرية طالما الطلب لم يتم قبوله.</p>` : ""}
    ${canRate ? `<button class="btn b-orange btn-full" data-rate-booking="${b.bookingId}">تقييم الطرف الآخر</button>` : ""}
  </article>`;
}

function myBookings(role, userId, filter) {
  const list = state.bookings.filter(b => {
    if (role === "client") return b.clientId === userId;
    return b.outletId === userId || b.clientId === userId;
  });
  const map = {
    running: ["pending", "accepted", "in_progress"],
    approved: ["accepted"],
    previous: ["completed", "cancelled", "expired"] };

  return list.filter(b => map[filter].includes(b.status));
}

function activeBooking() {
  if (state.user.role === "client") return state.bookings.find(b => b.clientId === state.user.uid && ["accepted", "in_progress"].includes(b.status));
  return state.bookings.find(b => (b.outletId === state.user.uid || b.createdById === state.user.uid) && ["accepted", "in_progress"].includes(b.status));
}

function outletStats(uidValue) {
  const done = state.bookings.filter(b => b.outletId === uidValue && b.status === "completed");
  return { count: done.length, amount: done.reduce((s, b) => s + Number(b.amount || 0), 0) };
}

function avgRating(toUserId) {
  const arr = state.ratings.filter(r => r.toUserId === toUserId);
  if (!arr.length) return 0;
  return +(arr.reduce((s, r) => s + r.stars, 0) / arr.length).toFixed(1);
}

function avgByFrom(fromUserId) {
  const arr = state.ratings.filter(r => r.fromUserId === fromUserId);
  if (!arr.length) return 0;
  return +(arr.reduce((s, r) => s + r.stars, 0) / arr.length).toFixed(1);
}

function requestTypeLabel(t) {
  return { withdraw: "سحب", deposit: "شحن", discharge: "تفريغ" }[t] || "شحن";
}

function statusAr(s) {
  return { pending: "قيد الانتظار", accepted: "مقبول", in_progress: "قيد التنفيذ", awaiting_auto_completion: "بانتظار الإكمال التلقائي", completed: "مكتمل", cancelled: "ملغي", expired: "منتهي" }[s] || s;
}

function formatBookingDate(ts) {
  const ms = tsToMs(ts);
  if (!ms) return "-";
  return new Date(ms).toLocaleString("ar-IQ", { year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" });
}

function handleBookingSideEffects() {
  if (!state.user || ["admin", "pending"].includes(state.user.role)) return;
  if (state.modal === "show-token" && state.pending?.bookingId) {
    const b = state.bookings.find(x => x.bookingId === state.pending.bookingId);
    if (b?.status === "completed") {
      closeModal();
      return;
    }
  }
  const freshCompleted = state.bookings.find(b => {
    if (b.status !== "completed") return false;
    if (!(b.clientId === state.user.uid || b.outletId === state.user.uid || b.createdById === state.user.uid)) return false;
    if (state.ratings.find(r => r.bookingId === b.bookingId && r.fromUserId === state.user.uid)) return false;
    const promptAt = Number(b.completionPromptAtMs || 0);
    if (!promptAt || Date.now() - promptAt > 5 * 60 * 1000) return false;
    return true;
  });
  if (freshCompleted && state.modal !== "rating") {
    const target = ratingTargetUserId(freshCompleted);
    if (target) {
      state.pending = { targetUserId: target, bookingId: freshCompleted.bookingId };
      state.modal = "rating";
      render();
      return;
    }
  }
}

function remain(ts) {
  const t = Number(ts || 0);
  const left = Math.max(0, t - Date.now());
  const m = Math.floor(left / 60000);
  const s = Math.floor(left % 60000 / 1000);
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

function distanceKm(a, b) {
  if (!a || !b || a.lat == null || a.lng == null || b.lat == null || b.lng == null) return 0;
  const R = 6371;
  if (Math.abs(a.lat - b.lat) < 0.0001 && Math.abs(a.lng - b.lng) < 0.0001) return 0;
  const dLat = (b.lat - a.lat) * Math.PI / 180;
  const dLng = (b.lng - a.lng) * Math.PI / 180;
  const lat1 = a.lat * Math.PI / 180;
  const lat2 = b.lat * Math.PI / 180;
  const x = Math.sin(dLat / 2) ** 2 + Math.sin(dLng / 2) ** 2 * Math.cos(lat1) * Math.cos(lat2);
  const d = 2 * R * Math.asin(Math.sqrt(x));
  return d < 0.03 ? 0 : Number(d.toFixed(2));
}

function distanceBandLabel(km) {
  const d = Number(km || 0);
  if (d <= 5) return "قريب";
  if (d <= 7) return "متوسط البعد";
  if (d <= 10) return "بعيد";
  return "بعيد جدا";
}

function expiryMs(v) {
  if (typeof v === "number") return v;
  if (v?.toMillis) return Number(v.toMillis());
  if (v?.seconds) return Number(v.seconds) * 1000;
  const n = Number(v);
  return Number.isFinite(n) ? n : NaN;
}

async function myLocation(forceRefresh = false) {
  if (!forceRefresh && currentUserLocation) return currentUserLocation;
  const lastKnown = currentUserLocation;
  currentUserLocation = null;
  if (!navigator.geolocation) {
    console.warn(`${APP_BOOT_LOG} geolocation unavailable: navigator.geolocation is missing`);
    return null;
  }
  console.info(`${APP_BOOT_LOG} geolocation APIs`, { hasGetCurrentPosition: typeof navigator.geolocation.getCurrentPosition === "function", hasWatchPosition: typeof navigator.geolocation.watchPosition === "function" });

  const getPosition = options => new Promise(resolve => {
    console.info(`${APP_BOOT_LOG} geolocation.getCurrentPosition start`, { forceRefresh, ...options });
    navigator.geolocation.getCurrentPosition(pos => {
      const candidate = { lat: pos.coords.latitude, lng: pos.coords.longitude };
      currentUserLocation = candidate;
      console.info(`${APP_BOOT_LOG} geolocation.getCurrentPosition success`, {
        lat: candidate.lat,
        lng: candidate.lng,
        accuracy: pos.coords.accuracy
      });
      resolve(candidate);
    }, err => {
      console.warn(`${APP_BOOT_LOG} geolocation.getCurrentPosition failed`, {
        code: err?.code,
        message: err?.message,
        denied: err?.code === 1,
        unavailable: err?.code === 2,
        timeout: err?.code === 3
      });
      resolve(null);
    }, options);
  });

  const highAccuracy = await getPosition({ enableHighAccuracy: true, timeout: 10000, maximumAge: 0 });
  if (highAccuracy) return highAccuracy;

  const normalAccuracy = await getPosition({ enableHighAccuracy: false, timeout: 15000, maximumAge: 120000 });
  if (normalAccuracy) return normalAccuracy;

  if (lastKnown) {
    console.info(`${APP_BOOT_LOG} using last known location fallback`, lastKnown);
    currentUserLocation = lastKnown;
    return lastKnown;
  }

  currentUserLocation = null;
  return null;
}

async function warmupLocationAfterLogin() {
  if (!state.user?.uid || state.user.uid === "admin" || !navigator.geolocation) return;
  try {
    console.info(`${APP_BOOT_LOG} warmup location after login start`, { uid: state.user.uid });
    const loc = await myLocation(true);
    console.info(`${APP_BOOT_LOG} warmup location after login result`, {
      ok: !!loc,
      lat: loc?.lat ?? null,
      lng: loc?.lng ?? null
    });
  } catch (err) {
    console.warn(`${APP_BOOT_LOG} warmup location after login failed`, {
      message: err?.message || String(err)
    });
  }
}

async function requireLocationForAction(reason = "request") {
  console.info(`${APP_BOOT_LOG} requireLocationForAction`, { reason });
  const location = await myLocation(true);
  if (location) return location;
  const saved = state.user?.location;
  if (saved && Number.isFinite(Number(saved.lat)) && Number.isFinite(Number(saved.lng))) {
    const fallback = { lat: Number(saved.lat), lng: Number(saved.lng) };
    console.warn(`${APP_BOOT_LOG} using saved profile location fallback`, { reason, fallback });
    if (reason === "create-booking" || reason === "accept-booking") {
      showToast("تعذر قراءة موقعك الحالي مباشرة، تم استخدام آخر موقع محفوظ", "warning");
    }
    return fallback;
  }
  console.warn(`${APP_BOOT_LOG} location unavailable for action`, { reason });
  if (reason === "create-booking") {
    showToast("يجب السماح بمشاركة موقعك الحالي لإتمام الطلب", "warning");
  } else if (reason === "accept-booking") {
    showToast("يجب السماح بمشاركة موقعك الحالي لقبول الطلب", "warning");
  } else {
    showToast("تعذر جلب موقعك الحالي، حاول مرة أخرى", "warning");
  }
  return null;
}

function openBookingInGoogleMaps(bookingId) {
  const booking = state.bookings.find(b => b.bookingId === bookingId || b.bookingDocId === bookingId);
  if (!booking) return showToast("تعذر تحديد بيانات الرحلة", "warning");
  const isOutletUser = state.user?.uid && booking.outletId === state.user.uid;
  const target = isOutletUser ? booking.clientLocation || booking.ownerOutletLocation : booking.outletLocation || booking.ownerOutletLocation;
  if (!target || target.lat == null || target.lng == null) return showToast("موقع الطرف الآخر غير متوفر", "warning");
  const origin = currentUserLocation && currentUserLocation.lat != null && currentUserLocation.lng != null ?
  `&origin=${encodeURIComponent(`${currentUserLocation.lat},${currentUserLocation.lng}`)}` :
  "";
  const destination = encodeURIComponent(`${target.lat},${target.lng}`);
  const url = `https://www.google.com/maps/dir/?api=1&destination=${destination}${origin}&travelmode=driving`;
  window.open(url, "_blank", "noopener,noreferrer");
}

function escapeHtml(v) {
  return String(v).replace(/[&<>'"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[c]);
}

async function hashToken(value) {
  const enc = new TextEncoder().encode(String(value || ""));
  const buf = await crypto.subtle.digest("SHA-256", enc);
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, "0")).join("");
}

async function getOwnedActiveBookingsCount(uidValue) {
  const q = query(collection(db, "bookings"), where("clientId", "==", uidValue), where("status", "in", ["pending", "accepted", "in_progress"]));
  const snap = await getDocs(q);
  return snap.size;
}

async function getAcceptedActiveBookingsCount(uidValue) {
  const q = query(collection(db, "bookings"), where("outletId", "==", uidValue), where("status", "in", ["accepted", "in_progress"]));
  const snap = await getDocs(q);
  return snap.size;
}

function monitorExpiry() {
  setInterval(async () => {
    const now = Date.now();
    const pending = state.bookings.filter(b => ["pending", "accepted", "in_progress"].includes(b.status) && Number(b.expiresAt) < now);
    const awaiting = state.bookings.filter(b => b.status === "awaiting_auto_completion" && Number(b.awaitingAutoCompletionUntil) < now);
    for (const b of pending) {
      if (!b.bookingDocId) continue;
      await updateDoc(doc(db, "bookings", b.bookingDocId), { status: "expired" });
      await logAction("expire_booking", state.user?.uid || "system", { bookingId: b.bookingId, status: "expired" });
    }
    for (const b of awaiting) {
      if (!b.bookingDocId) continue;
      await updateDoc(doc(db, "bookings", b.bookingDocId), { status: "completed" });
      await logAction("auto_complete_booking", state.user?.uid || "system", { bookingId: b.bookingId });
    }
  }, 5000);
}

function loadMaps() {
  if (window.google?.maps) return Promise.resolve();
  if (window.__gm) return window.__gm;
  window.__gm = new Promise((resolve, reject) => {
    const cb = `gm_${Date.now()}`;
    const timeout = setTimeout(() => {
      console.warn(`${APP_BOOT_LOG} Google Maps load timeout`);
      delete window[cb];
      reject(new Error("google_maps_timeout"));
    }, 10000);
    window[cb] = () => {
      clearTimeout(timeout);
      resolve();
      delete window[cb];
    };
    const s = document.createElement("script");
    s.src = `https://maps.googleapis.com/maps/api/js?key=${GOOGLE_MAPS_API_KEY}&language=ar&callback=${cb}`;
    s.async = true;
    s.defer = true;
    s.onerror = err => {
      clearTimeout(timeout);
      console.warn(`${APP_BOOT_LOG} Google Maps failed to load`, err);
      reject(err);
    };
    document.head.appendChild(s);
  });
  return window.__gm;
}

async function drawGoogleMap(id, booking) {
  try {
    if (!window.mapLoaded) {
      await loadMaps();
      window.mapLoaded = true;
    } else if (!window.google?.maps) {
      await loadMaps();
    }
  } catch (err) {
    console.warn(`${APP_BOOT_LOG} map draw aborted due to maps load failure`, err);
    return showToast("تعذر تحميل الخريطة حالياً", "warning");
  }
  if (!window.google?.maps) return;
  const el = document.getElementById(id);
  if (!el || !booking) return;
  const c = booking.clientLocation;
  const o = booking.outletLocation;
  if (!booking.clientLocation || !booking.outletLocation || c.lat == null || c.lng == null || o.lat == null || o.lng == null) {
    return showToast("الموقع غير متوفر بعد");
  }

  let map = mapInstances[id];
  if (!map) {
    map = new google.maps.Map(el, {
      center: c,
      zoom: 13,
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: false });

    mapInstances[id] = map;
  }

  if (map.__clientMarker) map.__clientMarker.setMap(null);
  if (map.__outletMarker) map.__outletMarker.setMap(null);
  if (map.__path) map.__path.setMap(null);

  map.__clientMarker = new google.maps.Marker({ position: c, map, title: "العميل", icon: "https://maps.google.com/mapfiles/ms/icons/blue-dot.png" });
  map.__outletMarker = new google.maps.Marker({ position: o, map, title: "المنفذ", icon: "https://maps.google.com/mapfiles/ms/icons/orange-dot.png" });

  const path = [
  new google.maps.LatLng(c.lat, c.lng),
  new google.maps.LatLng(o.lat, o.lng)];

  map.__path = new google.maps.Polyline({
    path,
    geodesic: true,
    strokeColor: "#16a34a",
    strokeOpacity: 1,
    strokeWeight: 4,
    map });


  const bounds = new google.maps.LatLngBounds();
  bounds.extend(c);
  bounds.extend(o);
  map.fitBounds(bounds, 40);

  setupMapCountdown(booking);
}

function setupMapCountdown(booking) {
  clearInterval(mapCountdownInterval);
  mapCountdownInterval = setInterval(async () => {
    const counter = root.querySelector(".counter");
    if (!counter) {
      clearInterval(mapCountdownInterval);
      mapCountdownInterval = null;
      return;
    }
    const left = remain(booking.expiresAt?.toMillis?.() || booking.expiresAt);
    counter.textContent = left;
    const isEnded = left === "00:00";
    if (!isEnded || mapCancelBusy) return;
    mapCancelBusy = true;
    clearInterval(mapCountdownInterval);
    mapCountdownInterval = null;
    if (booking.bookingDocId && ["pending", "accepted", "in_progress"].includes(booking.status)) {
      await updateDoc(doc(db, "bookings", booking.bookingDocId), { status: "expired" });
    }
    mapCancelBusy = false;
    render();
  }, 1000);
}


function isRequester(booking) {
  if (!booking || !state.user) return false;
  if (booking.clientId) return booking.clientId === state.user.uid;
  return booking.createdById === state.user.uid;
}

function ratingTargetUserId(booking) {
  if (!booking || !state.user) return null;
  if (booking.clientId === state.user.uid) return booking.outletId;
  if (booking.clientId && booking.outletId === state.user.uid) return booking.clientId;
  if (!booking.clientId && booking.createdById === state.user.uid) return booking.outletId;
  if (!booking.clientId && booking.outletId === state.user.uid) return booking.createdById;
  return null;
}

async function editName() {
  const key = state.user.role === "outlet" ? "outletName" : "fullName";
  const current = state.user[key] || "";
  const next = prompt("أدخل الاسم الجديد", current);
  if (!next || !next.trim()) return;
  await updateDoc(doc(db, "users", state.user.uid), { [key]: next.trim() });
}

async function ensureSupportChat(chatId) {
  const ref = doc(db, "support_chats", chatId);
  const snap = await getDoc(ref);
  if (!snap.exists()) {
    await setDoc(ref, { participants: [chatId, "admin"], lastMessage: "", updatedAt: serverTimestamp(), updatedAtMs: Date.now() });
  }
  return ref;
}

function scrollSupportToBottom() {
  const box = root.querySelector("#supportMessages");
  if (box) box.scrollTop = box.scrollHeight;
}


async function notifyAdminSupportInbox(chatId, text, tripId = null) {
  try {
    await addDoc(collection(db, "notifications"), {
      toUserId: "admin",
      type: "support_message",
      bookingId: tripId || chatId || null,
      title: "رسالة دعم جديدة",
      body: String(text || "").slice(0, 120),
      isRead: false,
      createdAt: serverTimestamp() });

  } catch (err) {
    console.warn(`${APP_BOOT_LOG} admin support notification write failed`, err);
  }
}

async function submitSupportMessage(e) {
  e.preventDefault();
  const message = String(new FormData(e.target).get("message") || "").trim();
  if (!message) return;
  if (!spamGuard("message", SPAM_LIMITS.message)) return showToast("تم تجاوز حد الرسائل مؤقتاً", "warning");
  const chatId = state.user.uid;
  const tripId = String(state.pending?.supportTripId || "").trim();
  try {
    await ensureSupportChat(chatId);
    await addDoc(collection(db, "support_chats", chatId, "messages"), {
      senderId: state.user.uid,
      senderRole: state.user.role || "user",
      text: message,
      source: tripId ? "trip_support" : "general_support",
      tripId: tripId || null,
      createdAt: serverTimestamp() });

    await updateDoc(doc(db, "support_chats", chatId), {
      lastMessage: message,
      updatedAt: serverTimestamp(),
      updatedAtMs: Date.now(),
      isClosed: false,
      source: tripId ? "trip_support" : "general_support",
      lastTripId: tripId || null });

    await notifyAdminSupportInbox(chatId, message, tripId || null);
    e.target.reset();
    setTimeout(scrollSupportToBottom, 20);
  } catch (err) {
    console.error(`${APP_BOOT_LOG} submitSupportMessage failed`, err);
    showToast("تعذر إرسال الرسالة في الدعم", "error");
  }
}

async function submitAdminSupportMessage(e) {
  e.preventDefault();
  const targetId = state.pending?.supportUid;
  if (!targetId) return;
  const message = String(new FormData(e.target).get("message") || "").trim();
  if (!message) return;
  if (!spamGuard("message", SPAM_LIMITS.message)) return showToast("تم تجاوز حد الرسائل مؤقتاً", "warning");
  try {
    await ensureSupportChat(targetId);
    await addDoc(collection(db, "support_chats", targetId, "messages"), {
      senderId: state.user?.authUid || state.user?.uid || "admin",
      senderRole: "admin",
      text: message,
      createdAt: serverTimestamp() });

    await updateDoc(doc(db, "support_chats", targetId), { lastMessage: message, updatedAt: serverTimestamp(), updatedAtMs: Date.now(), isClosed: false });
    await sendPushNotification(targetId, "رد جديد من الدعم", message.slice(0, 80), null);
    e.target.reset();
    setTimeout(scrollSupportToBottom, 20);
  } catch (err) {
    console.error(`${APP_BOOT_LOG} submitAdminSupportMessage failed`, err);
    showToast("تعذر إرسال الرسالة من الدعم", "error");
  }
}


async function ensureBookingChat(bookingId, booking = null) {
  if (!bookingId) return;
  const ref = doc(db, "booking_chats", bookingId);
  const snap = await getDoc(ref);
  if (snap.exists()) return;
  const b = booking || state.bookings.find(x => x.bookingId === bookingId || x.bookingDocId === bookingId) || {};
  const participants = [b.clientId, b.outletId, b.createdById].filter(Boolean);
  await setDoc(ref, { participants: [...new Set(participants)], createdAt: serverTimestamp(), updatedAt: serverTimestamp() }, { merge: true });
}

async function openBookingChat(bookingId) {
  if (!bookingId || !state.user) return;
  if (bookingChatUnsub) {
    bookingChatUnsub();
    bookingChatUnsub = null;
  }
  if (adminSupportChatUnsub) {
    adminSupportChatUnsub();
    adminSupportChatUnsub = null;
  }
  state.pending = { ...(state.pending || {}), bookingChatId: bookingId };
  const booking = state.bookings.find(x => x.bookingId === bookingId || x.bookingDocId === bookingId);
  await ensureBookingChat(bookingId, booking);
  if (booking?.bookingDocId && state.user.uid === booking.clientId) {
    await updateDoc(doc(db, "bookings", booking.bookingDocId), { unreadForClient: 0 });
  } else if (booking?.bookingDocId && state.user.uid === booking.outletId) {
    await updateDoc(doc(db, "bookings", booking.bookingDocId), { unreadForOutlet: 0 });
  }
  state.modal = "booking-chat";
  bookingChatUnsub = onSnapshot(query(collection(db, "booking_chats", bookingId, "messages"), orderBy("createdAt")), snap => {
    state.bookingMessages = snap.docs.map(d => ({ messageId: d.id, ...d.data() }));
    render();
    setTimeout(() => {
      const box = root.querySelector("#bookingMessages");
      if (box) box.scrollTop = box.scrollHeight;
    }, 20);
  });
  render();
}

async function submitBookingChatMessage(e) {
  e.preventDefault();
  const bookingId = state.pending?.bookingChatId;
  if (!bookingId || !state.user) return;
  const message = String(new FormData(e.target).get("message") || "").trim();
  if (!message) return;
  if (!spamGuard("message", SPAM_LIMITS.message)) return showToast("تم تجاوز حد الرسائل مؤقتاً", "warning");
  try {
    const b = state.bookings.find(x => x.bookingId === bookingId || x.bookingDocId === bookingId);
    await ensureBookingChat(bookingId, b);
    await addDoc(collection(db, "booking_chats", bookingId, "messages"), {
      senderId: state.user.uid,
      senderRole: state.user.role || "user",
      text: message,
      createdAt: serverTimestamp() });

    const toUserId = b ? b.clientId === state.user.uid ? b.outletId : b.clientId : null;
    if (b?.bookingDocId && toUserId) {
      if (toUserId === b.clientId) {
        await updateDoc(doc(db, "bookings", b.bookingDocId), { unreadForClient: increment(1), chatMessagesCount: increment(1) });
      } else if (toUserId === b.outletId) {
        await updateDoc(doc(db, "bookings", b.bookingDocId), { unreadForOutlet: increment(1), chatMessagesCount: increment(1) });
      }
    }
    if (toUserId) {
      await addNotification(toUserId, "booking_chat", bookingId, "رسالة جديدة", message.slice(0, 80));
      await sendPushNotification(toUserId, "رسالة جديدة في العملية", message.slice(0, 80), bookingId);
    }
    e.target.reset();
  } catch (err) {
    console.error(`${APP_BOOT_LOG} submitBookingChatMessage failed`, err);
    showToast("تعذر إرسال الرسالة في المحادثة", "error");
  }
}

async function submitBuyPoints(e) {
  e.preventDefault();
  if (!state.user) return;
  if (!window.Stripe) return showToast("Stripe غير متاح حالياً");
  const fd = new FormData(e.target);
  const [pointsStr, amountStr] = String(fd.get("pack") || "10:10").split(":");
  const points = Number(pointsStr || 0);
  const amountUsd = Number(amountStr || 0);
  const stripe = window.Stripe(STRIPE_PUBLISHABLE_KEY);
  setLoading(true);
  await addDoc(collection(db, "payments"), {
    userId: state.user.uid,
    points,
    amountUsd,
    method: "stripe_checkout",
    status: "pending",
    createdAt: serverTimestamp() });

  const res = await fetchWithTimeout("/create-checkout-session", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ userId: state.user.uid, points, amountUsd }) });

  if (!res.ok) {
    setLoading(false);
    return showToast("تعذر إنشاء جلسة الدفع");
  }
  const session = await res.json();
  setLoading(false);
  if (!session?.id) return showToast("بيانات جلسة الدفع غير صحيحة");
  await stripe.redirectToCheckout({ sessionId: session.id });
}

async function submitReward(e) {
  e.preventDefault();
  if (state.user?.uid !== "admin") return;
  const fd = new FormData(e.target);
  await addDoc(collection(db, "rewards"), {
    title: String(fd.get("title") || "").trim(),
    pointsRequired: Number(fd.get("pointsRequired") || 0),
    description: String(fd.get("description") || "").trim(),
    active: true,
    createdAt: serverTimestamp() });

  showToast("تم حفظ المكافأة");
  e.target.reset();
}

async function toggleReward(rewardId) {
  if (state.user?.uid !== "admin") return;
  const r = rewardsCache.find(x => x.rewardId === rewardId);
  if (!r) return;
  await updateDoc(doc(db, "rewards", rewardId), { active: r.active === false });
}

async function redeemReward(rewardId) {
  if (!state.user) return;
  const r = rewardsCache.find(x => x.rewardId === rewardId && x.active !== false);
  if (!r) return;
  const points = Number(state.user.points || 0);
  const need = Number(r.pointsRequired || 0);
  if (points < need) return showToast("النقاط غير كافية");
  await updateDoc(doc(db, "users", state.user.uid), { points: increment(-need) });
  await addDoc(collection(db, "reward_redemptions"), {
    userId: state.user.uid,
    rewardId,
    pointsUsed: need,
    createdAt: serverTimestamp() });

  showToast("تم استبدال المكافأة بنجاح");
  closeModal();
}


function openInAppCall(bookingId) {
  const b = state.bookings.find(x => x.bookingId === bookingId || x.bookingDocId === bookingId);
  if (!b) return showToast("تعذر تحديد بيانات الاتصال", "warning");
  state.pending = { ...(state.pending || {}), callBookingId: bookingId };
  state.modal = "in-app-call";
  render();
}

async function sendInAppCallInvite(bookingId) {
  const b = state.bookings.find(x => x.bookingId === bookingId || x.bookingDocId === bookingId);
  if (!b || !state.user?.uid) return showToast("تعذر بدء المكالمة", "warning");
  const peerId = state.user.uid === b.clientId ? b.outletId : b.clientId || b.createdById;
  if (!peerId) return showToast("الطرف الآخر غير متوفر", "warning");
  await addNotification(peerId, "incoming_call", b.bookingId || b.bookingDocId || "", "مكالمة داخل التطبيق", "الطرف الآخر يطلب مكالمة صوتية داخل التطبيق");
  await sendPushNotification(peerId, "مكالمة داخل التطبيق", "الطرف الآخر يطلب مكالمة صوتية داخل التطبيق", b.bookingId || b.bookingDocId || "");
  showToast("تم إرسال دعوة المكالمة للطرف الآخر", "success");
  closeModal();
}

function renderNotificationsTab() {
  const list = state.notifications.filter(n => n.toUserId === state.user.uid);
  return `<h3>الإشعارات</h3><div class="list">${list.map(n => `<article class="item ${n.isRead ? "" : "unread-item"}" data-open-notification="${n.notificationId}"><h4>${escapeHtml(n.title || "إشعار")}</h4><p class="muted">${escapeHtml(n.body || "")}</p><p class="muted">${new Date(n.createdAt?.seconds ? n.createdAt.seconds * 1000 : Date.now()).toLocaleString("ar-IQ")}</p></article>`).join("") || '<p class="muted">لا توجد إشعارات.</p>'}</div>`;
}

async function submitBroadcastNotification(e) {
  e.preventDefault();
  if (state.user?.uid !== "admin") return;
  const fd = new FormData(e.target);
  const title = String(fd.get("title") || "").trim();
  const body = String(fd.get("body") || "").trim();
  if (!title || !body) return showToast("يرجى إدخال عنوان ومحتوى", "warning");
  const recipients = state.users.filter(u => u.uid && u.uid !== "admin");
  setLoading(true);
  try {
    for (const u of recipients) {
      await addNotification(u.uid, "admin_broadcast", "", title, body);
      await sendPushNotification(u.uid, title, body, null);
    }
    showToast("تم إرسال الإشعار العام", "success");
    closeModal();
  } finally {
    setLoading(false);
  }
}

async function addNotification(toUserId, type, bookingId, title, body) {
  await addDoc(collection(db, "notifications"), { toUserId, type, bookingId, title, body, isRead: false, createdAt: serverTimestamp() });
}

async function openNotification(notificationId) {
  const note = state.notifications.find(n => n.notificationId === notificationId);
  if (!note) return;
  await updateDoc(doc(db, "notifications", notificationId), { isRead: true });
  state.tab = "requests";
  showToast(note.title || "إشعار", "info");
}

function pushEndpoint() {
  return "https://sendpushnotification-m54tsl5ubq-uc.a.run.app";
}

function userPushToken(uidValue = "") {
  return String(state.users.find(u => u.uid === uidValue)?.fcmToken || "").trim();
}

async function getUserFcmTokenById(userId = "") {
  const cleanId = String(userId || "").trim();
  if (!cleanId) return "";
  try {
    const snap = await getDoc(doc(db, "users", cleanId));
    if (!snap.exists()) return "";
    return String(snap.data()?.fcmToken || "").trim();
  } catch (err) {
    console.warn(`${APP_BOOT_LOG} getUserFcmTokenById failed`, err);
    return "";
  }
}

async function postPushNotificationRequest({ targetToken = "", title = "", body = "", bookingId = "" }) {
  console.info(`${APP_BOOT_LOG} frontend push sending disabled (Firestore trigger handles push)`, {
    bookingId: bookingId || "",
    hasTargetToken: !!targetToken,
    title
  });
  return false;
}

function showStatusToastForCurrentUser(booking, title, body = "") {
  if (!state.user || !booking) return;
  const isParty = booking.clientId === state.user.uid || booking.outletId === state.user.uid || booking.createdById === state.user.uid;
  if (!isParty) return;
  showToast(body ? `${title} - ${body}` : title, "info");
}

async function sendPushNotification(toUserId, title, body, bookingId = null) {
  if (!toUserId) {
    console.warn(`${APP_BOOT_LOG} sendPushNotification skipped: missing toUserId`, { title, bookingId: bookingId || "" });
    return false;
  }
  console.info(`${APP_BOOT_LOG} sendPushNotification skipped on frontend (handled by backend trigger)`, {
    toUserId,
    title,
    bookingId: bookingId || ""
  });
  if (toUserId === state.user?.uid) {
    showToast(body ? `${title} - ${body}` : title, "info");
  }
  return false;
}

function maybePromptRatingForBooking(booking) {
  if (!state.user || state.user.uid === "admin" || !booking) return;
  if (booking.status !== "completed") return;
  const bookingKey = booking.bookingId || booking.bookingDocId;
  if (!bookingKey) return;
  const isParty = booking.clientId === state.user.uid || booking.outletId === state.user.uid || booking.createdById === state.user.uid;
  if (!isParty) return;
  const alreadyRated = state.ratings.find(r => (r.bookingId === booking.bookingId || r.bookingId === booking.bookingDocId) && r.fromUserId === state.user.uid);
  if (alreadyRated) return;
  const target = ratingTargetUserId(booking);
  if (!target) return;
  state.pending = { targetUserId: target, bookingId: bookingKey };
  state.modal = "rating";
  render();
}

function processBookingStatusTransitions(bookings) {
  for (const booking of bookings) {
    const bookingKey = booking.bookingDocId || booking.bookingId;
    if (!bookingKey) continue;
    const oldStatus = bookingStatusCache.get(bookingKey);
    const newStatus = booking.status;
    if (oldStatus && oldStatus !== newStatus) {
      if (newStatus === "accepted" && booking.clientId) {
        showStatusToastForCurrentUser(booking, "تم قبول الطلب", "تم قبول طلبك وأصبح جاهزاً للتتبع");
        sendPushNotification(booking.clientId, "تم قبول طلبك – اضغط للتتبع", "تم قبول طلبك – اضغط للتتبع", booking.bookingId || bookingKey);
      }
      if (newStatus === "in_progress" && booking.outletId) {
        showStatusToastForCurrentUser(booking, "وصول الطلب", "تم تسجيل وصول العميل إلى موقع العملية");
        sendPushNotification(booking.outletId, "العميل وصل إلى موقع العملية", "العميل وصل إلى موقع العملية", booking.bookingId || bookingKey);
      }
      if (newStatus === "completed") {
        showStatusToastForCurrentUser(booking, "انتهاء العملية", "تم إكمال العملية بنجاح");
        if (booking.clientId) sendPushNotification(booking.clientId, "اكتملت العملية", "تم إكمال العملية بنجاح", booking.bookingId || bookingKey);
        if (booking.outletId) sendPushNotification(booking.outletId, "اكتملت العملية", "تم إكمال العملية بنجاح", booking.bookingId || bookingKey);
        maybePromptRatingForBooking(booking);
      }
    }
    if (!oldStatus && newStatus === "completed") {
      const promptAt = Number(booking.completionPromptAtMs || 0);
      if (promptAt && Date.now() - promptAt <= 10 * 60 * 1000) maybePromptRatingForBooking(booking);
    }
    bookingStatusCache.set(bookingKey, newStatus);
  }
}

async function getMessagingServiceWorkerRegistration() {
  if (!("serviceWorker" in navigator)) return null;
  try {
    return await navigator.serviceWorker.register("./firebase-messaging-sw.js", { scope: "./" });
  } catch (err) {
    console.warn(`${APP_BOOT_LOG} service worker registration failed`, err);
    return null;
  }
}

async function scheduleAdminTestNotification() {
  if (!("Notification" in window)) return showToast("الإشعارات غير مدعومة في هذا المتصفح", "warning");
  const permission = await Notification.requestPermission();
  if (permission !== "granted") return showToast("يجب السماح بالإشعارات أولاً", "warning");
  const token = userPushToken(state.user?.uid || "");
  if (!token) return showToast("لم يتم تسجيل توكن الإشعار لهذا الجهاز بعد", "warning");
  console.info(`${APP_BOOT_LOG} admin test push skipped on frontend (backend trigger architecture)`, {
    uid: state.user?.uid || "",
    hasToken: !!token
  });
  showToast("تم تعطيل الإرسال المباشر من الواجهة، الإرسال يتم عبر Cloud Functions (Firestore triggers)", "info");
}

async function setupFcm() {
  try {
    if (!("Notification" in window) || !state.user?.uid) return;

    if (!FCM_VAPID_KEY) {
      console.warn(`${APP_BOOT_LOG} FCM skipped: missing VAPID key`, {
        hint: "Set FCM_VAPID_KEY in script.js to your Firebase Web Push certificate key."
      });
      return;
    }

    const reg = await getMessagingServiceWorkerRegistration();
    if (!reg) {
      console.warn(`${APP_BOOT_LOG} FCM skipped: service worker registration unavailable`);
      return;
    }

    const permission = await Notification.requestPermission();
    console.info(`${APP_BOOT_LOG} notification permission`, permission);

    if (permission !== "granted") {
      return;
    }

    messaging = messaging || getMessaging(app);

    const token = await getFcmToken(messaging, {
      vapidKey: FCM_VAPID_KEY,
      serviceWorkerRegistration: reg
    });

    if (!token) {
      console.warn(`${APP_BOOT_LOG} FCM token missing after getToken`);
      return;
    }

    console.info(`${APP_BOOT_LOG} FCM token`, token);

    await setDoc(
      doc(db, "users", state.user.uid),
      {
        uid: state.user.uid,
        fcmToken: token,
        fcmUpdatedAt: serverTimestamp()
      },
      { merge: true }
    );
    console.info(`${APP_BOOT_LOG} FCM token saved`, { path: `users/${state.user.uid}`, field: "fcmToken" });

    if (state.user) {
      state.user = { ...state.user, fcmToken: token };
    }

    onFcmMessage(messaging, payload => {
      console.info(`${APP_BOOT_LOG} foreground push payload`, payload);
      if (Notification.permission === "granted") {
        try {
          new Notification(payload?.notification?.title || "إشعار جديد", {
            body: payload?.notification?.body || "",
            icon: "/icon.png"
          });
        } catch (err) {
          console.warn(`${APP_BOOT_LOG} foreground Notification API failed`, err);
        }
      }
      showToast(payload?.notification?.title || "إشعار جديد", "info");
    });
  } catch (err) {
    console.warn(`${APP_BOOT_LOG} FCM setup failed`, {
      message: err?.message || String(err),
      code: err?.code || "",
      stack: err?.stack || ""
    });
  }
}

function renderPending() {
  root.innerHTML = `
    ${h("بانتظار موافقة الإدارة", "تم إنشاء حساب المنفذ بنجاح")}
    <section class="card">
      <p class="muted">حسابك قيد المراجعة حالياً. سيتم تفعيل الدخول بعد موافقة الإدارة.</p>
      <button class="btn b-danger btn-full" id="logoutBtn">تسجيل خروج</button>
    </section>
  `;
  bindShared();
}

async function bootstrapApp() {
  console.info(`${APP_BOOT_LOG} bootstrap started`);
  if (!root) return;
  await initAuthPersistence();

  try {
    const redirectResult = await getRedirectResult(auth);
    if (redirectResult?.user) {
      const pendingRole = localStorage.getItem("qiqa_pending_role") || state.role || "client";
      await ensureUserProfileFromAuth(redirectResult.user, { role: pendingRole, governorate: localStorage.getItem("qiqa_pending_governorate") || "" });
      localStorage.removeItem("qiqa_pending_role");
      localStorage.removeItem("qiqa_pending_governorate");
      await handlePostLogin(redirectResult.user.uid, redirectResult.user);
    }
  } catch (err) {
    console.warn(`${APP_BOOT_LOG} redirect login failed`, err);
  }

  onAuthStateChanged(auth, async u => {
    try {
      if (!u) {
        clearUnsubs();
            state.user = null;
        if (state.view !== "admin") state.view = "role";
        render();
        return;
      }
      if (String(u.email || "").toLowerCase() === ADMIN_EMAIL.toLowerCase()) {
        state.user = { uid: "admin", authUid: u.uid, role: "admin", fullName: "مدير النظام", email: u.email || ADMIN_EMAIL };
        state.view = "admin";
        state.tab = "pending";
        setupRealtime();
        render();
        return;
      }
      if (state.view === "admin") return;
      await handlePostLogin(u.uid, u);
    } catch (err) {
      console.error(`${APP_BOOT_LOG} onAuthStateChanged handler failed`, err);
      state.view = "role";
      render();
    }
  });

  window.addEventListener("error", e => {
    logAction("client_error", state.user?.uid || "guest", { message: e.message || "unknown" });
  });

  monitorExpiry();
  render();
  console.info(`${APP_BOOT_LOG} bootstrap finished`);
}

bootstrapApp().catch(err => {
  console.error(`${APP_BOOT_LOG} bootstrap failed`, err);
  if (root) {
    root.innerHTML = `<section class="card" style="margin-top:24px;text-align:center;"><h2>تعذر تشغيل التطبيق</h2><p class="muted">تحقق من إعدادات Netlify واسم النطاق المضاف في Firebase ثم أعد المحاولة.</p></section>`;
  }
});
//# sourceURL=pen.js
  

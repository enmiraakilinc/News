// Saat ekranı. Haber ve sohbeti sunucudan okur, kısa cevap yollar.
import fetch from '@system.fetch';
import vibrator from '@system.vibrator';

var SERVER = '';
var TOKEN = 'WATCH_TOKEN';
var LETTERS = 'abcçdefgğhıijklmnoöprsştuüvyz'.split('');

export default {
  data: {
    tab: 'news',
    news: [],
    article: -1,
    chats: [],
    chat: -1,
    draft: '',
    keys: LETTERS,
    status: '',
    seen: {},
  },
  onInit() {
    this.loadNews();
    this.loadChats();
    this.timer = setInterval(this.loadChats.bind(this), 8000);
  },
  onDestroy() {
    clearInterval(this.timer);
  },
  showNews() { this.tab = 'news'; this.article = -1; },
  showChats() { this.tab = 'chats'; this.chat = -1; this.loadChats(); },
  openArticle(e) { this.article = e.detail.index; },
  closeArticle() { this.article = -1; },
  openChat(e) { this.chat = e.detail.index; },
  closeChat() { this.chat = -1; },
  typeKey(e) { this.draft += this.keys[e.detail.index]; },
  backspace() { this.draft = this.draft.slice(0, -1); },
  space() { this.draft += ' '; },
  quickOk() { this.draft = 'Tamam'; this.send(); },
  quickSoon() { this.draft = 'Geliyorum'; this.send(); },
  quickLater() { this.draft = 'Sonra yazarım'; this.send(); },
  loadNews() {
    var page = this;
    if (!SERVER) { page.status = 'Sunucu adresi tanımlı değil.'; return; }
    fetch.fetch({
      url: SERVER + '/api/watch/news',
      responseType: 'json',
      success: function (res) {
        var data = typeof res.data === 'string' ? JSON.parse(res.data) : res.data;
        page.news = data.items || [];
      },
      fail: function () { page.status = 'Haberler alınamadı.'; },
    });
  },
  loadChats() {
    var page = this;
    if (!SERVER) { page.status = 'Sunucu adresi tanımlı değil.'; return; }
    fetch.fetch({
      url: SERVER + '/api/watch/chats?token=' + TOKEN,
      responseType: 'json',
      success: function (res) {
        var data = typeof res.data === 'string' ? JSON.parse(res.data) : res.data;
        page.notice(data.chats || []);
        page.chats = data.chats || [];
      },
      fail: function () { page.status = 'Sohbetler alınamadı.'; },
    });
  },
  notice(chats) {
    var buzz = false;
    for (var i = 0; i < chats.length; i++) {
      var messages = chats[i].messages || [];
      var last = messages.length ? messages[messages.length - 1] : null;
      var previous = this.seen[chats[i].id];
      if (last && previous && previous !== last.id && !last.fromMe) buzz = true;
      if (last) this.seen[chats[i].id] = last.id;
    }
    if (!buzz) return;
    vibrator.vibrate({mode: 'short'});
    setTimeout(function () { vibrator.vibrate({mode: 'short'}); }, 180);
  },
  send() {
    if (this.chat < 0 || !this.draft) return;
    var page = this;
    var text = this.draft;
    fetch.fetch({
      url: SERVER + '/api/watch/send',
      method: 'POST',
      header: {'Content-Type': 'application/json'},
      data: {token: TOKEN, chatId: this.chats[this.chat].id, text: text},
      responseType: 'json',
      success: function () {
        page.draft = '';
        page.status = 'Gönderildi.';
        page.loadChats();
      },
      fail: function () { page.status = 'Mesaj gönderilemedi.'; },
    });
  },
};

/* ==========================================================================
   Vanessa O'Neill — REALTOR® | Site interactions
   ========================================================================== */
(function () {
  'use strict';

  /* ---------- Mobile nav toggle ---------- */
  var toggle = document.querySelector('.nav-toggle');
  var body = document.body;
  if (toggle) {
    toggle.addEventListener('click', function () {
      var open = body.classList.toggle('nav-open');
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    // Close drawer when a link is tapped
    document.querySelectorAll('.nav__link, .nav .nav__cta').forEach(function (link) {
      link.addEventListener('click', function () {
        body.classList.remove('nav-open');
        toggle.setAttribute('aria-expanded', 'false');
      });
    });
    // Close on Escape
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && body.classList.contains('nav-open')) {
        body.classList.remove('nav-open');
        toggle.setAttribute('aria-expanded', 'false');
      }
    });
  }

  /* ---------- Header background on scroll ---------- */
  var header = document.querySelector('.site-header');
  if (header && !header.classList.contains('solid')) {
    var onScroll = function () {
      if (window.scrollY > 40) header.classList.add('scrolled');
      else header.classList.remove('scrolled');
    };
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
  }

  /* ---------- Current year in footer ---------- */
  document.querySelectorAll('[data-year]').forEach(function (el) {
    el.textContent = new Date().getFullYear();
  });

  /* ---------- Reveal on scroll ---------- */
  var revealEls = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window && revealEls.length) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('in');
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.14, rootMargin: '0px 0px -40px 0px' });
    revealEls.forEach(function (el) { io.observe(el); });
  } else {
    revealEls.forEach(function (el) { el.classList.add('in'); });
  }

  /* ---------- Testimonial slider ---------- */
  var slider = document.querySelector('[data-testi]');
  if (slider) {
    var slides = Array.prototype.slice.call(slider.querySelectorAll('.testi'));
    var dotsWrap = slider.querySelector('.testi-dots');
    var current = 0, timer = null;

    // Build dots
    slides.forEach(function (_, i) {
      var b = document.createElement('button');
      b.type = 'button';
      b.setAttribute('aria-label', 'Show testimonial ' + (i + 1));
      if (i === 0) b.classList.add('active');
      b.addEventListener('click', function () { go(i); restart(); });
      if (dotsWrap) dotsWrap.appendChild(b);
    });
    var dots = dotsWrap ? Array.prototype.slice.call(dotsWrap.children) : [];

    function go(n) {
      slides[current].classList.remove('active');
      if (dots[current]) dots[current].classList.remove('active');
      current = (n + slides.length) % slides.length;
      slides[current].classList.add('active');
      if (dots[current]) dots[current].classList.add('active');
    }
    function next() { go(current + 1); }
    function prev() { go(current - 1); }
    function restart() { if (timer) clearInterval(timer); timer = setInterval(next, 7000); }

    var nextBtn = slider.querySelector('[data-testi-next]');
    var prevBtn = slider.querySelector('[data-testi-prev]');
    if (nextBtn) nextBtn.addEventListener('click', function () { next(); restart(); });
    if (prevBtn) prevBtn.addEventListener('click', function () { prev(); restart(); });

    restart();
  }

  /* ---------- Home valuation address hand-off ---------- */
  document.querySelectorAll('[data-valuation-form]').forEach(function (form) {
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var input = form.querySelector('input');
      var addr = input ? encodeURIComponent(input.value.trim()) : '';
      window.location.href = 'contact.html?intent=valuation' + (addr ? '&address=' + addr : '');
    });
  });

  /* ---------- Mortgage calculator ---------- */
  var calc = document.querySelector('[data-mortgage]');
  if (calc) {
    var els = {
      price: calc.querySelector('[name="price"]'),
      down: calc.querySelector('[name="down"]'),
      rate: calc.querySelector('[name="rate"]'),
      term: calc.querySelector('[name="term"]'),
      tax: calc.querySelector('[name="tax"]'),
      ins: calc.querySelector('[name="ins"]'),
      outMonthly: calc.querySelector('[data-out="monthly"]'),
      outPI: calc.querySelector('[data-out="pi"]'),
      outTax: calc.querySelector('[data-out="tax"]'),
      outIns: calc.querySelector('[data-out="ins"]'),
      outLoan: calc.querySelector('[data-out="loan"]'),
      downPct: calc.querySelector('[data-out="downpct"]')
    };

    var fmt = function (n) {
      return '$' + (isFinite(n) ? Math.round(n) : 0).toLocaleString('en-US');
    };

    function compute() {
      var price = parseFloat(els.price.value) || 0;
      var down = parseFloat(els.down.value) || 0;
      var rate = parseFloat(els.rate.value) || 0;
      var term = parseFloat(els.term.value) || 30;
      var taxRate = els.tax ? (parseFloat(els.tax.value) || 0) : 0;
      var insYr = els.ins ? (parseFloat(els.ins.value) || 0) : 0;

      var loan = Math.max(price - down, 0);
      var i = (rate / 100) / 12;
      var n = term * 12;
      var pi = i > 0 ? loan * (i * Math.pow(1 + i, n)) / (Math.pow(1 + i, n) - 1) : (n > 0 ? loan / n : 0);
      var monthlyTax = (price * (taxRate / 100)) / 12;
      var monthlyIns = insYr / 12;
      var total = pi + monthlyTax + monthlyIns;

      if (els.outMonthly) els.outMonthly.textContent = fmt(total);
      if (els.outPI) els.outPI.textContent = fmt(pi);
      if (els.outTax) els.outTax.textContent = fmt(monthlyTax);
      if (els.outIns) els.outIns.textContent = fmt(monthlyIns);
      if (els.outLoan) els.outLoan.textContent = fmt(loan);
      if (els.downPct) {
        var pct = price > 0 ? (down / price) * 100 : 0;
        els.downPct.textContent = pct.toFixed(1) + '%';
      }
    }

    calc.querySelectorAll('input, select').forEach(function (el) {
      el.addEventListener('input', compute);
      el.addEventListener('change', compute);
    });
    compute();
  }

  /* ---------- Contact form (client-side demo handler) ---------- */
  document.querySelectorAll('[data-contact-form]').forEach(function (form) {
    // Pre-fill intent/address from query string (from valuation hand-off)
    try {
      var params = new URLSearchParams(window.location.search);
      var intent = params.get('intent');
      var address = params.get('address');
      if (intent) {
        var sel = form.querySelector('[name="interest"]');
        if (sel) {
          var match = Array.prototype.find.call(sel.options, function (o) {
            return o.value.toLowerCase().indexOf(intent.toLowerCase()) !== -1;
          });
          if (match) sel.value = match.value;
        }
      }
      if (address) {
        var msg = form.querySelector('[name="message"]');
        if (msg && !msg.value) msg.value = 'I would like a home valuation for: ' + address;
      }
    } catch (err) { /* no-op */ }

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var status = form.querySelector('.form-status');
      var required = form.querySelectorAll('[required]');
      var ok = true;
      required.forEach(function (f) {
        if (!f.value.trim()) { ok = false; f.style.borderColor = '#c0524a'; }
        else { f.style.borderColor = ''; }
      });
      if (!ok) {
        if (status) {
          status.className = 'form-status error show';
          status.textContent = 'Please complete the required fields so I can get back to you.';
        }
        return;
      }
      // Demo behavior — no backend wired in the template.
      if (status) {
        status.className = 'form-status success show';
        status.textContent = 'Thank you! Your message has been prepared. Vanessa will be in touch shortly. '
          + '(This template form needs a form service or email backend connected before it sends live — see README.)';
      }
      form.reset();
    });
  });

})();

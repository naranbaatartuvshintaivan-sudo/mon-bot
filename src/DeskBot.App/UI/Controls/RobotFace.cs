using System;
using System.ComponentModel;
using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Effects;
using DeskBot.Core.Expressions;
using DeskBot.Core.Settings;

namespace DeskBot.App.UI.Controls;

/// <summary>
/// RobotFaceEngine — static зураг огт ашиглахгүй. Нүд бүрийг geometry-гоор (rounded rect − lid − bottom ellipse)
/// frame бүр бүтээж, expression хооронд параметрээр зөөлөн lerp хийнэ.
/// Анивчих, cursor дагах, "notice", click pulse, idle wander, theme-ийн effect-ууд бүгд энд.
/// </summary>
public sealed class RobotFace : FrameworkElement
{
    private const double TransitionSeconds = 0.24;

    private AppSettings _s = new();

    // Expression transition
    private Expression _expr = Expression.Idle;
    private FaceParameters _from = FaceLibrary.For(Expression.Idle);
    private FaceParameters _to = FaceLibrary.For(Expression.Idle);
    private double _transT = 1;

    // Харц
    private Point? _cursorLocal;
    private double _lastCursorMove = -100;
    private Vector _look;
    private Point? _glance;
    private double _glanceUntil;
    private Vector _idleLook;
    private double _idleLookUntil, _nextIdleAction = 6;

    // Цаг, анивчилт, pulse
    private double _time, _lastStamp = -1;
    private long _frame;
    private double _blink = 1, _blinkStart = -1, _nextBlink = 1.5;
    private double _notice, _clickPulse;
    private double _glitchUntil, _nextGlitch = 3;

    private bool _running, _paused;
    private readonly Random _rng = new();
    private readonly DropShadowEffect _glow = new() { ShadowDepth = 0, BlurRadius = 10, Opacity = 0.85, RenderingBias = RenderingBias.Performance };
    private static readonly Typeface GlyphFace = new(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal);

    public RobotFace()
    {
        Effect = _glow;
        SnapsToDevicePixels = false;
        Loaded += (_, _) => Start();
        Unloaded += (_, _) => Stop();
        IsVisibleChanged += (_, _) => { if (IsVisible) Start(); else Stop(); };
    }

    public void Bind(AppSettings settings)
    {
        _s.PropertyChanged -= OnSettingsChanged;
        _s = settings;
        _s.PropertyChanged += OnSettingsChanged;
        InvalidateVisual();
    }

    private void OnSettingsChanged(object? sender, PropertyChangedEventArgs e) => InvalidateVisual();

    public Expression Expression
    {
        get => _expr;
        set
        {
            if (value == _expr) return;
            _from = FaceParameters.Lerp(_from, _to, EyeMath.EaseOutCubic(_transT)); // дундаас нь эхэлнэ — үсрэлтгүй
            _to = FaceLibrary.For(value);
            _expr = value;
            _transT = 0;
        }
    }

    /// <summary>Game mode / hidden үед animation зогсоож CPU хэмнэнэ.</summary>
    public bool Paused
    {
        get => _paused;
        set { _paused = value; if (value) Stop(); else Start(); }
    }

    /// <summary>Global cursor (physical px). Face local DIP руу хөрвүүлнэ — multi-monitor DPI зөв.</summary>
    public void SetCursorScreen(int x, int y)
    {
        if (PresentationSource.FromVisual(this) is null) return;
        var p = PointFromScreen(new Point(x, y));
        if (_cursorLocal is { } old && (old - p).LengthSquared < 0.25) return;
        _cursorLocal = p;
        _lastCursorMove = _time;
    }

    /// <summary>Хаа нэгтээ click хийхэд тэр зүг рүү богино харна.</summary>
    public void Glance(int screenX, int screenY, double seconds = 0.7)
    {
        if (PresentationSource.FromVisual(this) is null) return;
        _glance = PointFromScreen(new Point(screenX, screenY));
        _glanceUntil = _time + seconds;
    }

    /// <summary>Robot дээр click — нүд түр томорно.</summary>
    public void Pulse() => _clickPulse = 1;

    private void Start()
    {
        if (_running || _paused || !IsVisible) return;
        _running = true;
        _lastStamp = -1;
        CompositionTarget.Rendering += OnRendering;
    }

    private void Stop()
    {
        if (!_running) return;
        _running = false;
        CompositionTarget.Rendering -= OnRendering;
    }

    private void OnRendering(object? sender, EventArgs e)
    {
        if (e is not RenderingEventArgs re) return;
        var stamp = re.RenderingTime.TotalSeconds;
        if (_lastStamp < 0) { _lastStamp = stamp; return; }
        var dt = stamp - _lastStamp;
        if (dt <= 0) return; // нэг frame-д давхар дуудагдсан
        _lastStamp = stamp;
        dt = Math.Min(dt, 0.05) * _s.AnimationSpeed;
        _time += dt;
        _frame++;

        Update(dt);

        // Performance mode: ~30fps
        if (_s.PerformanceMode && (_frame & 1) == 1) return;
        InvalidateVisual();
    }

    // ───────────────────────── Update ─────────────────────────

    private void Update(double dt)
    {
        var reduced = _s.ReducedMotion;
        _transT = Math.Min(1, _transT + dt / TransitionSeconds * (reduced ? 2 : 1));

        // Анивчилт
        var canBlink = _expr is not (Expression.Processing or Expression.Error or Expression.Listening);
        if (_blinkStart < 0 && canBlink && _time >= _nextBlink) _blinkStart = _time;
        _blink = 1;
        if (_blinkStart >= 0)
        {
            var phase = (_time - _blinkStart) / 0.16;
            if (phase >= 1) { _blinkStart = -1; ScheduleBlink(); }
            else _blink = EyeMath.BlinkOpenness(phase);
        }

        // Харах чиглэл
        var center = new Point(ActualWidth / 2, ActualHeight / 2);
        Vector target = default;
        var cursorFresh = _cursorLocal is not null && _time - _lastCursorMove < 8;

        if (_s.FollowCursor && _cursorLocal is { } c)
            target = LookAt(c, center);

        if (!cursorFresh || !_s.FollowCursor)
        {
            // Cursor хөдлөхгүй бол өөрөө эргэн тойрноо харна — "амьд" мэдрэмж
            if (_time >= _nextIdleAction)
            {
                _idleLook = new Vector((_rng.NextDouble() * 2 - 1) * 0.75, (_rng.NextDouble() * 2 - 1) * 0.4);
                _idleLookUntil = _time + 1.0 + _rng.NextDouble() * 1.2;
                _nextIdleAction = _time + 4 + _rng.NextDouble() * 8;
                if (_rng.NextDouble() < 0.35) _nextBlink = Math.Min(_nextBlink, _time + 0.3);
            }
            if (_time < _idleLookUntil) target = _idleLook;
        }

        if (_expr == Expression.NewMessage) target = new Vector(0.85, -0.6);
        else if (_expr == Expression.Sleepy) target = new Vector(0, 0.35);
        if (_glance is { } g && _time < _glanceUntil) target = LookAt(g, center);

        if (reduced) target *= 0.6;
        var k = EyeMath.SmoothFactor(dt, reduced ? 14 : 7.5);
        _look += (target - _look) * k;

        // Notice — cursor ойртоход нүд томорч, гэрэлтэнэ, нэг анивчина
        var near = _cursorLocal is { } cl && (cl - center).Length < 170 ? 1.0 : 0.0;
        var prev = _notice;
        _notice += (near - _notice) * EyeMath.SmoothFactor(dt, 6);
        if (prev < 0.5 && _notice >= 0.5 && _blinkStart < 0 && canBlink) _blinkStart = _time;

        _clickPulse = Math.Max(0, _clickPulse - dt * 2.8);

        if (_s.Theme == FaceTheme.Glitch && !reduced && _time >= _nextGlitch)
        {
            _glitchUntil = _time + 0.14 + _rng.NextDouble() * 0.14;
            _nextGlitch = _time + 2 + _rng.NextDouble() * 4;
        }

        UpdateGlow();
    }

    private Vector LookAt(Point p, Point center)
    {
        var (x, y) = EyeMath.LookVector(p.X - center.X, p.Y - center.Y, 420);
        return new Vector(x, y);
    }

    private void ScheduleBlink()
    {
        var mult = _expr == Expression.Sleepy ? 1.8 : 1.0;
        _nextBlink = _rng.NextDouble() < 0.12
            ? _time + 0.18                                     // давхар анивчилт
            : _time + (2.4 + _rng.NextDouble() * 3.6) * mult / _s.BlinkFrequency;
    }

    private void UpdateGlow()
    {
        if (_s.PerformanceMode || _s.GlowIntensity <= 0.01)
        {
            if (Effect is not null) Effect = null;
            return;
        }
        if (Effect is null) Effect = _glow;
        var p = CurrentParams(out var t);
        var col = CurrentColor(p, t);
        if (_glow.Color != col) _glow.Color = col;
        var blur = 4 + 16 * _s.GlowIntensity * p.Glow * (1 + 0.3 * _notice);
        if (Math.Abs(_glow.BlurRadius - blur) > 0.2) _glow.BlurRadius = blur;
        var op = Math.Clamp(0.4 + 0.55 * _s.GlowIntensity, 0, 1);
        if (Math.Abs(_glow.Opacity - op) > 0.01) _glow.Opacity = op;
    }

    // ───────────────────────── Color ─────────────────────────

    private FaceParameters CurrentParams(out double easedT)
    {
        easedT = EyeMath.EaseOutCubic(_transT);
        return FaceParameters.Lerp(_from, _to, easedT);
    }

    private Color ThemeColor(bool secondary = false) => _s.Theme switch
    {
        FaceTheme.Aurora => Hsv(secondary ? 275 + 35 * Math.Sin(_time * 0.45 + 1.3) : 190 + 45 * Math.Sin(_time * 0.6), 0.75, 1),
        FaceTheme.Matrix => secondary ? Color.FromRgb(0x0F, 0x7A, 0x2E) : Color.FromRgb(0x39, 0xFF, 0x6A),
        FaceTheme.Glitch => secondary ? Color.FromRgb(0xFF, 0x3D, 0xF5) : Color.FromRgb(0x7C, 0xF7, 0xFF),
        FaceTheme.Cyberpunk => secondary ? Color.FromRgb(0xFF, 0xE1, 0x4D) : Color.FromRgb(0xFF, 0x2E, 0x88),
        FaceTheme.Minimal => Color.FromRgb(0xF2, 0xF5, 0xF7),
        FaceTheme.Custom => ParseHex(_s.CustomColor),
        _ => secondary ? Color.FromRgb(0x2A, 0x7B, 0xFF) : Color.FromRgb(0x33, 0xE1, 0xFF),
    };

    private Color ColorOf(in FaceParameters p) => p.SemanticColor is uint u ? FromArgb(u) : ThemeColor();

    private Color CurrentColor(in FaceParameters p, double t) =>
        Brighten(Mix(ColorOf(_from), ColorOf(_to), t), p.Brightness);

    private Brush BuildFill(Color col, in FaceParameters p, double t)
    {
        Brush b;
        if (_s.Theme == FaceTheme.Aurora && _from.SemanticColor is null && _to.SemanticColor is null)
        {
            b = new LinearGradientBrush(Brighten(ThemeColor(), p.Brightness), Brighten(ThemeColor(true), p.Brightness), new Point(0, 0), new Point(1, 1));
        }
        else if (_s.Theme == FaceTheme.Matrix && p.SemanticColor is null)
        {
            b = new SolidColorBrush(Color.FromArgb(0xB0, col.R, col.G, col.B));
        }
        else
        {
            b = new SolidColorBrush(col);
        }
        b.Freeze();
        return b;
    }

    // ───────────────────────── Render ─────────────────────────

    protected override void OnRender(DrawingContext dc)
    {
        double W = ActualWidth, H = ActualHeight;
        if (W < 4 || H < 4) return;

        var p = CurrentParams(out var t);
        var col = CurrentColor(p, t);
        var fill = BuildFill(col, p, t);
        var reduced = _s.ReducedMotion;

        var (aspect, round) = _s.EyeShape switch
        {
            EyeShape.Pill => (0.58, 0.5),
            EyeShape.Circle => (1.0, 0.5),
            EyeShape.Square => (0.92, 0.16),
            _ => (0.8, 0.36),
        };
        var baseH = Math.Min(H * 0.62 * _s.EyeSize, H * 0.92);
        var baseW = baseH * aspect;
        var spacing = Math.Max(baseW * 1.95 * _s.EyeSpacing, baseW * 1.2);
        var breathe = reduced || _s.PerformanceMode ? 1 : 1 + 0.022 * Math.Sin(_time * 1.7);
        var bounce = reduced ? 0 : -p.Bounce * H * Math.Abs(Math.Sin(_time * p.BounceSpeed * 0.5));
        var pop = 1 + 0.08 * _notice + 0.22 * _clickPulse;
        var cx = W / 2 + _look.X * baseW * 0.6;
        var cy = H / 2 + p.OffsetY * H + bounce + _look.Y * baseH * 0.28;
        var glitching = _s.Theme == FaceTheme.Glitch && _time < _glitchUntil;

        for (var side = -1; side <= 1; side += 2)
        {
            var sc = (side > 0 ? p.RightEyeScale : 1) * breathe * pop;
            var w = baseW * p.EyeWidth * sc;
            var h = baseH * p.EyeHeight * sc;
            var ex = cx + side * spacing / 2;
            var ey = cy + (side > 0 ? p.RightEyeLift * H : 0);

            if (p.Overlay.HasFlag(FaceOverlay.Ring)) { DrawRingEye(dc, ex, ey, Math.Max(w, h), col, side); continue; }
            if (p.Overlay.HasFlag(FaceOverlay.Wave)) { DrawWaveEye(dc, ex, ey, w, h, fill, side); continue; }
            if (p.Overlay.HasFlag(FaceOverlay.PixelX)) { DrawPixelX(dc, ex, ey, Math.Min(w, h) * 1.1, col); continue; }

            var hb = h * Math.Max(0.07, _blink);
            var geo = BuildEye(ex, ey, w, hb, Math.Min(w, hb) * round, p.LidTop, p.LidAngle, p.BottomCut, side);

            if (glitching)
            {
                var jitter = (_rng.NextDouble() - 0.5) * 4;
                dc.PushTransform(new TranslateTransform(-2.5 + jitter, 0));
                dc.DrawGeometry(Frozen(Color.FromArgb(0x90, 0xFF, 0x30, 0x60)), null, geo);
                dc.Pop();
                dc.PushTransform(new TranslateTransform(2.5 + jitter, 0));
                dc.DrawGeometry(Frozen(Color.FromArgb(0x90, 0x30, 0xF0, 0xFF)), null, geo);
                dc.Pop();
            }

            dc.DrawGeometry(fill, null, geo);

            if (_s.Theme == FaceTheme.Matrix && !_s.PerformanceMode && p.SemanticColor is null)
                DrawMatrixRain(dc, geo, ex, ey, w, hb, side);
        }

        DrawOverlays(dc, p, col, W, H, spacing, baseW, baseH);
    }

    private static Geometry BuildEye(double cx, double cy, double w, double h, double r,
        double lidTop, double lidAngle, double bottomCut, int side)
    {
        var rect = new Rect(cx - w / 2, cy - h / 2, w, h);
        r = Math.Min(r, Math.Min(w, h) / 2);
        Geometry g = new RectangleGeometry(rect, r, r);

        if (lidTop > 0.001)
        {
            // Lid-ийн доод ирмэг (cx, top+lidTop*h)-ээр дамжина. + angle = дотор тал доош (уурласан)
            var pivotY = rect.Top + lidTop * h;
            var lid = new RectangleGeometry(new Rect(cx - w * 1.5, pivotY - h * 2, w * 3, h * 2))
            {
                Transform = new RotateTransform(lidAngle * -side, cx, pivotY),
            };
            g = new CombinedGeometry(GeometryCombineMode.Exclude, g, lid);
        }

        if (bottomCut > 0.001)
        {
            // Доороос эллипсээр тайрч ∩ хэлбэр (баярласан нүд)
            var rx = w * 0.78;
            var ry = h * 0.95;
            var ecy = rect.Bottom + ry - bottomCut * h * 1.25;
            g = new CombinedGeometry(GeometryCombineMode.Exclude, g, new EllipseGeometry(new Point(cx, ecy), rx, ry));
        }
        return g;
    }

    private void DrawRingEye(DrawingContext dc, double x, double y, double d, Color col, int side)
    {
        var r = d * 0.4;
        var track = new Pen(Frozen(Color.FromArgb(0x40, col.R, col.G, col.B)), d * 0.12);
        dc.DrawEllipse(null, track, new Point(x, y), r, r);

        var a0 = _time * 5.5 * side;
        var a1 = a0 + Math.PI * 0.62;
        var sg = new StreamGeometry();
        using (var ctx = sg.Open())
        {
            ctx.BeginFigure(new Point(x + r * Math.Cos(a0), y + r * Math.Sin(a0)), false, false);
            ctx.ArcTo(new Point(x + r * Math.Cos(a1), y + r * Math.Sin(a1)), new Size(r, r), 0, false, SweepDirection.Clockwise, true, true);
        }
        sg.Freeze();
        var pen = new Pen(Frozen(col), d * 0.16) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        dc.DrawGeometry(null, pen, sg);
    }

    private void DrawWaveEye(DrawingContext dc, double x, double y, double w, double h, Brush fill, int side)
    {
        const int bars = 4;
        var bw = w / 6;
        var gap = (w - bars * bw) / (bars - 1);
        for (var k = 0; k < bars; k++)
        {
            var amp = 0.25 + 0.75 * Math.Abs(Math.Sin(_time * 7 + k * 0.9 + side));
            var bh = h * amp;
            var bx = x - w / 2 + k * (bw + gap);
            dc.DrawRoundedRectangle(fill, null, new Rect(bx, y - bh / 2, bw, bh), bw / 2, bw / 2);
        }
    }

    private void DrawPixelX(DrawingContext dc, double x, double y, double size, Color col)
    {
        if ((int)(_time * 9) % 11 == 0) return; // "эвдэрсэн" анивчилт
        const int n = 5;
        var px = size / n;
        var b = Frozen(col);
        for (var i = 0; i < n; i++)
            for (var j = 0; j < n; j++)
                if (i == j || i + j == n - 1)
                    dc.DrawRectangle(b, null, new Rect(x - size / 2 + i * px + 0.5, y - size / 2 + j * px + 0.5, px - 1, px - 1));
    }

    private void DrawMatrixRain(DrawingContext dc, Geometry clip, double ex, double ey, double w, double h, int side)
    {
        dc.PushClip(clip);
        const int cols = 4;
        var cw = w / cols;
        var sq = cw * 0.62;
        for (var k = 0; k < cols; k++)
        {
            var speed = h * (1.4 + (k % 3) * 0.45);
            var span = h + sq * 4;
            var head = (_time * speed + (k * 13.7 + side * 5)) % span - sq * 2;
            var x = ex - w / 2 + k * cw + (cw - sq) / 2;
            var top = ey - h / 2;
            for (var tr = 0; tr < 3; tr++)
            {
                var a = (byte)(tr switch { 0 => 255, 1 => 140, _ => 60 });
                dc.DrawRectangle(Frozen(Color.FromArgb(a, 0xC8, 0xFF, 0xD8)), null, new Rect(x, top + head - tr * sq * 1.25, sq, sq));
            }
        }
        dc.Pop();
    }

    private void DrawOverlays(DrawingContext dc, in FaceParameters p, Color col, double W, double H, double spacing, double baseW, double baseH)
    {
        var o = p.Overlay;
        if (o == FaceOverlay.None) return;
        var right = Math.Min(W / 2 + spacing / 2 + baseW * 1.05, W - baseH * 0.35);
        var left = Math.Max(W / 2 - spacing / 2 - baseW * 1.05, baseH * 0.35);
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var brush = Frozen(col);

        if (o.HasFlag(FaceOverlay.Sparkles))
        {
            var spots = new[] { (left, H * 0.22), (right, H * 0.3), (W / 2, H * 0.1) };
            for (var i = 0; i < spots.Length; i++)
            {
                var s = baseH * 0.2 * (0.55 + 0.45 * Math.Abs(Math.Sin(_time * 5 + i * 1.7)));
                DrawStar(dc, spots[i].Item1, spots[i].Item2, s, Frozen(Mix(col, Colors.White, 0.6)));
            }
        }
        if (o.HasFlag(FaceOverlay.Bubble))
        {
            var bw = baseW * 1.15; var bh = baseH * 0.55;
            var bx = right - bw / 2; var by = H * 0.08;
            dc.DrawRoundedRectangle(brush, null, new Rect(bx, by, bw, bh), bh / 2.2, bh / 2.2);
            for (var i = 0; i < 3; i++)
            {
                var a = (byte)(120 + 135 * Math.Max(0, Math.Sin(_time * 6 - i * 0.8)));
                dc.DrawEllipse(Frozen(Color.FromArgb(a, 0x05, 0x06, 0x08)), null, new Point(bx + bw * (0.28 + i * 0.22), by + bh / 2), bh * 0.12, bh * 0.12);
            }
        }
        if (o.HasFlag(FaceOverlay.Clock))
        {
            var r = baseH * 0.28; var c = new Point(right, H * 0.3);
            var pen = new Pen(brush, Math.Max(1.2, r * 0.18));
            dc.DrawEllipse(null, pen, c, r, r);
            var a = _time * 3;
            dc.DrawLine(pen, c, new Point(c.X + Math.Sin(a) * r * 0.75, c.Y - Math.Cos(a) * r * 0.75));
            dc.DrawLine(pen, c, new Point(c.X + r * 0.45, c.Y));
        }
        if (o.HasFlag(FaceOverlay.Battery))
        {
            var bw = baseW * 0.95; var bh = baseH * 0.42; var bx = right - bw / 2; var by = H * 0.18;
            var pen = new Pen(brush, 1.2);
            dc.DrawRoundedRectangle(null, pen, new Rect(bx, by, bw, bh), 1.5, 1.5);
            dc.DrawRectangle(brush, null, new Rect(bx + bw, by + bh * 0.3, bw * 0.1, bh * 0.4));
            if ((int)(_time * 2) % 2 == 0)
                dc.DrawRectangle(Frozen(FromArgb(FaceLibrary.Red)), null, new Rect(bx + 2, by + 2, (bw - 4) * 0.2, bh - 4));
        }
        if (o.HasFlag(FaceOverlay.Notes))
        {
            for (var i = 0; i < 2; i++)
            {
                var f = (_time * 0.6 + i * 0.5) % 1;
                var a = (byte)(255 * (1 - f));
                DrawGlyph(dc, i == 0 ? "♪" : "♫", left - i * baseW * 0.3, H * 0.75 - f * H * 0.6, baseH * 0.48, Color.FromArgb(a, col.R, col.G, col.B), dpi);
            }
        }
        if (o.HasFlag(FaceOverlay.Question))
            DrawGlyph(dc, "?", right, H * 0.32 + Math.Sin(_time * 3) * H * 0.04, baseH * 0.62, col, dpi);
        if (o.HasFlag(FaceOverlay.Zzz))
        {
            for (var i = 0; i < 3; i++)
            {
                var f = (_time * 0.4 + i / 3.0) % 1;
                DrawGlyph(dc, "z", right + f * baseW * 0.5, H * 0.6 - f * H * 0.5, baseH * (0.25 + f * 0.3), Color.FromArgb((byte)(230 * (1 - f)), col.R, col.G, col.B), dpi);
            }
        }
        if (o.HasFlag(FaceOverlay.Warning))
        {
            var s = baseH * 0.5; var c = new Point(right, H * 0.32);
            var tri = new StreamGeometry();
            using (var ctx = tri.Open())
            {
                ctx.BeginFigure(new Point(c.X, c.Y - s * 0.55), true, true);
                ctx.LineTo(new Point(c.X + s * 0.55, c.Y + s * 0.45), true, false);
                ctx.LineTo(new Point(c.X - s * 0.55, c.Y + s * 0.45), true, false);
            }
            tri.Freeze();
            dc.DrawGeometry(Frozen(FromArgb(FaceLibrary.Amber)), null, tri);
            DrawGlyph(dc, "!", c.X, c.Y + s * 0.05, s * 0.7, Color.FromRgb(0x05, 0x06, 0x08), dpi);
        }
    }

    private static void DrawStar(DrawingContext dc, double x, double y, double s, Brush b)
    {
        var g = new StreamGeometry();
        using (var ctx = g.Open())
        {
            var i = s * 0.25;
            ctx.BeginFigure(new Point(x, y - s), true, true);
            ctx.PolyLineTo(new[]
            {
                new Point(x + i, y - i), new Point(x + s, y), new Point(x + i, y + i),
                new Point(x, y + s), new Point(x - i, y + i), new Point(x - s, y), new Point(x - i, y - i),
            }, true, false);
        }
        g.Freeze();
        dc.DrawGeometry(b, null, g);
    }

    private void DrawGlyph(DrawingContext dc, string text, double x, double y, double size, Color c, double dpi)
    {
        if (size < 1) return;
        var ft = new FormattedText(text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, GlyphFace, size, Frozen(c), dpi);
        dc.DrawText(ft, new Point(x - ft.Width / 2, y - ft.Height / 2));
    }

    // ───────────────────────── Color helpers ─────────────────────────

    private static SolidColorBrush Frozen(Color c)
    {
        var b = new SolidColorBrush(c);
        b.Freeze();
        return b;
    }

    internal static Color FromArgb(uint argb) =>
        Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb);

    internal static Color ParseHex(string hex)
    {
        if (!AppSettings.IsHexColor(hex)) return Color.FromRgb(0x33, 0xE1, 0xFF);
        var v = Convert.ToUInt32(hex[1..], 16);
        return Color.FromRgb((byte)(v >> 16), (byte)(v >> 8), (byte)v);
    }

    private static Color Mix(Color a, Color b, double t)
    {
        t = Math.Clamp(t, 0, 1);
        static byte L(byte x, byte y, double k) => (byte)Math.Round(x + (y - x) * k);
        return Color.FromArgb(L(a.A, b.A, t), L(a.R, b.R, t), L(a.G, b.G, t), L(a.B, b.B, t));
    }

    private static Color Brighten(Color c, double k)
    {
        if (k <= 1)
            return Color.FromArgb(c.A, (byte)(c.R * k), (byte)(c.G * k), (byte)(c.B * k));
        return Mix(c, Color.FromArgb(c.A, 255, 255, 255), Math.Min(1, (k - 1) * 0.6));
    }

    private static Color Hsv(double h, double s, double v)
    {
        h = ((h % 360) + 360) % 360;
        var c = v * s;
        var x = c * (1 - Math.Abs(h / 60 % 2 - 1));
        var m = v - c;
        var (r, g, b) = (int)(h / 60) switch
        {
            0 => (c, x, 0d), 1 => (x, c, 0d), 2 => (0d, c, x),
            3 => (0d, x, c), 4 => (x, 0d, c), _ => (c, 0d, x),
        };
        return Color.FromRgb((byte)((r + m) * 255), (byte)((g + m) * 255), (byte)((b + m) * 255));
    }
}

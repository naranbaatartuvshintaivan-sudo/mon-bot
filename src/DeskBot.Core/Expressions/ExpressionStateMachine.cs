namespace DeskBot.Core.Expressions;

/// <summary>
/// Олон эх үүсвэрээс ирэх expression хүсэлтийг priority-оор шийдвэрлэнэ.
/// - Өндөр priority шууд ялна.
/// - Бага priority руу буухдаа MinHold хугацаа өнгөрөхийг хүлээнэ (анивчилт үүсгэхгүй).
/// - Хугацаатай layer-ууд Tick() дээр дуусна.
/// Thread-safe биш — UI thread дээр ашиглана.
/// </summary>
public sealed class ExpressionStateMachine
{
    private readonly Dictionary<ExpressionSource, Layer> _layers = new();
    private Expression _baseMood = Expression.Idle;
    private int _currentPriority;
    private DateTimeOffset _lastChange = DateTimeOffset.MinValue;

    public TimeSpan MinHold { get; set; } = TimeSpan.FromMilliseconds(250);

    public Expression Current { get; private set; } = Expression.Idle;

    public event Action<Expression>? Changed;

    public Expression BaseMood => _baseMood;

    public void SetBaseMood(Expression mood, DateTimeOffset now)
    {
        _baseMood = ExpressionRules.SanitizeBaseMood(mood);
        Evaluate(now, force: true);
    }

    public void Set(ExpressionSource source, Expression expression, DateTimeOffset now, TimeSpan? duration = null)
    {
        _layers[source] = new Layer(expression, duration is { } d ? now + d : null);
        Evaluate(now);
    }

    public void Clear(ExpressionSource source, DateTimeOffset now)
    {
        if (_layers.Remove(source))
            Evaluate(now);
    }

    public bool IsActive(ExpressionSource source) => _layers.ContainsKey(source);

    /// <summary>Хугацаа дууссан layer-уудыг цэвэрлэж, хойшлогдсон шилжилтийг хийнэ.</summary>
    public void Tick(DateTimeOffset now)
    {
        List<ExpressionSource>? expired = null;
        foreach (var (src, layer) in _layers)
        {
            if (layer.Until is { } u && u <= now)
                (expired ??= new()).Add(src);
        }
        if (expired is not null)
            foreach (var src in expired) _layers.Remove(src);

        Evaluate(now);
    }

    private void Evaluate(DateTimeOffset now, bool force = false)
    {
        var (next, priority) = Resolve(now);
        if (next == Current && priority == _currentPriority) return;

        // Доод priority руу буухдаа хэт хурдан солигдохоос сэргийлнэ
        if (!force && priority < _currentPriority && now - _lastChange < MinHold)
            return;

        var changed = next != Current;
        Current = next;
        _currentPriority = priority;
        if (changed)
        {
            _lastChange = now;
            Changed?.Invoke(next);
        }
    }

    private (Expression, int) Resolve(DateTimeOffset now)
    {
        Expression best = _baseMood;
        int bestPriority = 0;
        foreach (var (src, layer) in _layers)
        {
            if (layer.Until is { } u && u <= now) continue;
            var p = (int)src;
            if (p > bestPriority)
            {
                bestPriority = p;
                best = layer.Expression;
            }
        }
        return (best, bestPriority);
    }

    private readonly record struct Layer(Expression Expression, DateTimeOffset? Until);
}

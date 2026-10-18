// A Friday evening session continues into Saturday morning (KST).
// Public holidays need a separate exchange calendar; this gate covers weekends.
function isNightFuturesSession(now = new Date()) {
  const kst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const day = kst.getUTCDay();
  const hour = kst.getUTCHours();
  return (hour >= 18 && day >= 1 && day <= 5)
    || (hour < 5 && day >= 2 && day <= 6);
}

module.exports = { isNightFuturesSession };

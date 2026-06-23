const _directoryCache = new Map();
const _listingCache = new Map();

function buildUrl(params = {}) {
  const url = new URL("/api/public/businesses.php", window.location.origin);
  Object.entries(params).forEach(([key, value]) => {
    if (value === undefined || value === null || value === "") return;
    url.searchParams.set(key, String(value));
  });
  return url;
}

async function fetchBusinessesPage(params = {}) {
  const url = buildUrl(params);
  const res = await fetch(url.toString(), {
    credentials: "same-origin",
    headers: { Accept: "application/json" },
  });
  if (!res.ok) {
    throw new Error(`businesses fetch failed (${res.status})`);
  }
  const json = await res.json();
  return Array.isArray(json?.data) ? json.data : [];
}

async function fetchPaginated(params = {}, options = {}) {
  const pageSize = Math.max(1, Number(options.pageSize || params.limit || 100));
  const maxPages = Math.max(1, Number(options.maxPages || 1));
  const maxItems = Math.max(pageSize, Number(options.maxItems || pageSize));
  const out = [];

  for (let page = 1; page <= maxPages; page += 1) {
    const items = await fetchBusinessesPage({ ...params, limit: pageSize, page });
    if (!items.length) break;
    out.push(...items);
    if (items.length < pageSize || out.length >= maxItems) break;
  }

  return out.slice(0, maxItems);
}

function normalizeDirectoryOptions(options = {}) {
  return {
    status: options.status || "active",
    mode: "directory",
    pageSize: Math.max(20, Math.min(100, Number(options.pageSize || 100))),
    maxPages: Math.max(1, Math.min(6, Number(options.maxPages || 4))),
    maxItems: Math.max(50, Math.min(400, Number(options.maxItems || 400))),
  };
}

function normalizeListingParams(filters = {}) {
  const params = {
    status: filters.status || "active",
    mode: "list",
    city: filters.city || "",
    district: filters.district || "",
    neighborhood: filters.neighborhood || "",
    q: filters.q || "",
    pageSize: Math.max(20, Math.min(80, Number(filters.pageSize || 60))),
    maxPages: Math.max(1, Math.min(8, Number(filters.maxPages || 6))),
    maxItems: Math.max(60, Math.min(400, Number(filters.maxItems || 300))),
  };
  return params;
}

export async function loadDirectoryBusinesses(options = {}) {
  const config = normalizeDirectoryOptions(options);
  const key = JSON.stringify(config);
  if (!_directoryCache.has(key)) {
    _directoryCache.set(
      key,
      fetchPaginated(
        { status: config.status, mode: config.mode },
        {
          pageSize: config.pageSize,
          maxPages: config.maxPages,
          maxItems: config.maxItems,
        }
      ).catch((err) => {
        _directoryCache.delete(key);
        throw err;
      })
    );
  }
  return _directoryCache.get(key);
}

export async function loadListingBusinesses(filters = {}) {
  const config = normalizeListingParams(filters);
  const key = JSON.stringify(config);
  if (!_listingCache.has(key)) {
    _listingCache.set(
      key,
      fetchPaginated(
        {
          status: config.status,
          mode: "list",
          city: config.city,
          district: config.district,
          neighborhood: config.neighborhood,
          q: config.q,
        },
        {
          pageSize: config.pageSize,
          maxPages: config.maxPages,
          maxItems: config.maxItems,
        }
      ).catch((err) => {
        _listingCache.delete(key);
        throw err;
      })
    );
  }
  return _listingCache.get(key);
}

export function clearListingBusinessesCache() {
  _listingCache.clear();
}

// assets/sources/kopymanga_bl.js

const BL_KEYWORDS = ["耽美", "BL", "纯爱", "清水", "强强", "腹黑攻", "少年爱", "danmei"];

function isBLComic(comic) {
    if (!comic) return false;
    // 1. 检查题材/标签
    if (comic.theme && Array.isArray(comic.theme)) {
        for (const t of comic.theme) {
            if (t && (BL_KEYWORDS.includes(t.name) || BL_KEYWORDS.includes(t.path_word))) {
                return true;
            }
        }
    }
    // 2. 检查名称和简介
    if (comic.name) {
        for (const key of BL_KEYWORDS) {
            if (comic.name.toLowerCase().includes(key)) return true;
        }
    }
    if (comic.introduce) {
        for (const key of BL_KEYWORDS) {
            if (comic.introduce.toLowerCase().includes(key)) return true;
        }
    }
    return false;
}

const pendingRequests = {};
let nextRequestId = 1;

function resolveRequest(requestId, responseStr, errorStr) {
    const req = pendingRequests[requestId];
    if (req) {
        delete pendingRequests[requestId];
        if (errorStr) {
            req.reject(new Error(errorStr));
        } else {
            req.resolve(responseStr);
        }
    }
}

// 辅助方法：通过 Dart 宿主方法进行 HTTP 请求
async function httpGet(path, params = {}, hostKey = null) {
    const requestId = nextRequestId++;
    return new Promise((resolve, reject) => {
        pendingRequests[requestId] = { resolve, reject };
        sendMessage('httpGetAsync', JSON.stringify({
            requestId: requestId,
            path: path,
            params: params,
            hostKey: hostKey
        }));
    }).then(responseStr => {
        const response = JSON.parse(responseStr);
        if (response && response.error) {
            throw new Error(response.error);
        }
        return response;
    });
}

/**
 * 1. 获取主页漫画数据 (过滤出耽美漫画)
 */
async function getMangaHome() {
    const data = await httpGet("/api/v3/h5/discoverIndex/freeComic", {
        platform: 3,
        _update: true
    }, 'home');
    
    // 过滤推荐列表 (recs.list) 中的漫画
    if (data.recs && Array.isArray(data.recs.list)) {
        data.recs.list = data.recs.list.filter(item => {
            if (item && item.comic) {
                return isBLComic(item.comic);
            }
            return false;
        });
    }
    
    return JSON.stringify(data);
}

/**
 * 2. 搜索漫画 (过滤出耽美漫画)
 */
async function searchComics(query, offset = 0, limit = 20) {
    const data = await httpGet("/api/v3/search/comic", {
        platform: 3,
        q: query,
        limit: 30, // 索取更多数据以便进行 BL 筛选 (Kopymanga API 限制最大为 30)
        offset: offset,
        free_type: 1,
        _update: true
    });
    
    if (data.list && Array.isArray(data.list)) {
        const filteredList = data.list.filter(comic => isBLComic(comic));
        data.list = filteredList.slice(0, limit);
        data.total = filteredList.length;
    }
    
    return JSON.stringify(data);
}

/**
 * 3. 获取漫画详情
 */
async function getComicDetail(pathWord) {
    const data = await httpGet(`/api/v3/comic2/${pathWord}`, {
        platform: 3
    }, 'sd');
    return JSON.stringify(data);
}

/**
 * 4. 获取章节详情
 */
async function getChapterDetail(pathWord, chapterUuid) {
    const data = await httpGet(`/api/v3/comic/${pathWord}/chapter/${chapterUuid}`, {
        platform: 3
    }, 'sd');
    return JSON.stringify(data);
}

// ⚠️ رقم الواتساب الخاص بمتجر SPYDERX™ (بدون علامة +، مثال: 213550000000)
const WHATSAPP_NUMBER = "213550000000";

// 📦 جدول الولايات الجزائرية الـ 58 الكاملة مع أسعار التوصيل (مكتب و منزل)
const wilayasData = [
    { id: 1, name: "01 - أدرار", desk: 900, home: 1200 },
    { id: 2, name: "02 - الشلف", desk: 500, home: 700 },
    { id: 3, name: "03 - الأغواط", desk: 700, home: 950 },
    { id: 4, name: "04 - أم البواقي", desk: 550, home: 750 },
    { id: 5, name: "05 - باتنة", desk: 500, home: 700 },
    { id: 6, name: "06 - بجاية", desk: 500, home: 700 },
    { id: 7, name: "07 - بسكرة", desk: 600, home: 850 },
    { id: 8, name: "08 - بشار", desk: 900, home: 1200 },
    { id: 9, name: "09 - البليدة", desk: 400, home: 600 },
    { id: 10, name: "10 - البويرة", desk: 450, home: 650 },
    { id: 11, name: "11 - تبسة", desk: 550, home: 750 },
    { id: 12, name: "12 - تلمسان", desk: 550, home: 750 },
    { id: 13, name: "13 - تيارت", desk: 550, home: 750 },
    { id: 14, name: "14 - تيزي وزو", desk: 450, home: 650 },
    { id: 15, name: "15 - الجزائر العاصمة", desk: 350, home: 550 },
    { id: 16, name: "16 - الجلفة", desk: 600, home: 850 },
    { id: 17, name: "17 - جيجل", desk: 500, home: 700 },
    { id: 18, name: "18 - سطيف", desk: 450, home: 650 },
    { id: 19, name: "19 - سعيدة", desk: 550, home: 750 },
    { id: 20, name: "20 - سكيكدة", desk: 500, home: 700 },
    { id: 21, name: "21 - سيدي بلعباس", desk: 550, home: 750 },
    { id: 22, name: "22 - عنابة", desk: 500, home: 700 },
    { id: 23, name: "23 - قالمة", desk: 500, home: 700 },
    { id: 24, name: "24 - قسنطينة", desk: 450, home: 650 },
    { id: 25, name: "25 - المدية", desk: 500, home: 700 },
    { id: 26, name: "26 - مستغانم", desk: 500, home: 700 },
    { id: 27, name: "27 - المسيلة", desk: 550, home: 750 },
    { id: 28, name: "28 - معسكر", desk: 550, home: 750 },
    { id: 29, name: "29 - ورقلة", desk: 700, home: 950 },
    { id: 30, name: "30 - وهران", desk: 500, home: 700 },
    { id: 31, name: "31 - البيض", desk: 800, home: 1100 },
    { id: 32, name: "32 - إليزي", desk: 1000, home: 1400 },
    { id: 33, name: "33 - برج بوعريريج", desk: 450, home: 650 },
    { id: 34, name: "34 - بومرداس", desk: 400, home: 600 },
    { id: 35, name: "35 - الطارف", desk: 550, home: 750 },
    { id: 36, name: "36 - تندوف", desk: 1000, home: 1400 },
    { id: 37, name: "37 - تيسمسيلت", desk: 550, home: 750 },
    { id: 38, name: "38 - الوادي", desk: 700, home: 950 },
    { id: 39, name: "39 - خنشلة", desk: 550, home: 750 },
    { id: 40, name: "40 - سوق أهراس", desk: 550, home: 750 },
    { id: 41, name: "41 - تيبازة", desk: 400, home: 600 },
    { id: 42, name: "42 - ميلة", desk: 500, home: 700 },
    { id: 43, name: "43 - عين الدفلى", desk: 500, home: 700 },
    { id: 44, name: "44 - النعامة", desk: 800, home: 1100 },
    { id: 45, name: "45 - عين تموشنت", desk: 550, home: 750 },
    { id: 46, name: "46 - غرداية", desk: 700, home: 950 },
    { id: 47, name: "47 - غليزان", desk: 500, home: 700 },
    { id: 48, name: "48 - تقرت", desk: 700, home: 950 },
    { id: 49, name: "49 - جانت", desk: 1000, home: 1400 },
    { id: 50, name: "50 - المغير", desk: 700, home: 950 },
    { id: 51, name: "51 - المنيعة", desk: 800, home: 1100 },
    { id: 52, name: "52 - أولاد جلال", desk: 600, home: 850 },
    { id: 53, name: "53 - برج باجي مختار", desk: 900, home: 1200 },
    { id: 54, name: "54 - بني عباس", desk: 900, home: 1200 },
    { id: 55, name: "55 - تيميمون", desk: 900, home: 1200 },
    { id: 56, name: "56 - تقرت", desk: 700, home: 950 },
    { id: 57, name: "57 - إن صالح", desk: 900, home: 1200 },
    { id: 58, name: "58 - إن قزام", desk: 1000, home: 1400 }
];

// 🕸️ منتجات SPYDERX™ الأساسية
let products = [
    {
        id: 1,
        name: "SPYDERX Heavyweight Gothic Hoodie",
        category: "Hoodies",
        price: 4500,
        oldPrice: 5200,
        image: "https://i.postimg.cc/k4r7XM2q/file-00000000a73481f489f0e5f55cc0c8b0.png",
        description: "هودي ثقيل بقطن عالي الجودة، قصة Oversized مع تصميم عنكبوت قوطي مطرز بدقة.",
        isNew: true,
        isSale: true,
        sizes: ["S", "M", "L", "XL", "XXL"],
        outOfStockSizes: ["XXL"],
        colors: ["Black", "Dark Purple"],
        outOfStockColors: []
    },
    {
        id: 2,
        name: "SPIDBRICK Custom Star Baggy Jeans",
        category: "Jeans",
        price: 4800,
        oldPrice: 5500,
        image: "https://i.postimg.cc/k4r7XM2q/file-00000000a73481f489f0e5f55cc0c8b0.png",
        description: "جينز واسع بطابع الستريت وير، مطبوع بتفاصيل نجوم وعناكب داكنة.",
        isNew: true,
        isSale: false,
        sizes: ["30", "32", "34", "36"],
        outOfStockSizes: ["36"],
        colors: ["Washed Black", "Gothic Blue"],
        outOfStockColors: ["Gothic Blue"]
    }
];

let cart = [];
let favorites = [];
let currentFilter = 'all';
let selectedProduct = null;
let activeSize = '';
let activeColor = '';

document.addEventListener('DOMContentLoaded', () => {
    renderProducts();
    initWilayas();
    updateBadges();
});

function initWilayas() {
    const select = document.getElementById('orderWilaya');
    if (!select) return;
    select.innerHTML = '';
    wilayasData.forEach(w => {
        select.innerHTML += `<option value="${w.name}" data-desk="${w.desk}" data-home="${w.home}">${w.name}</option>`;
    });
    updateShippingPrices();
}

function updateShippingPrices() {
    const select = document.getElementById('orderWilaya');
    const deliveryTypeSelect = document.getElementById('orderDeliveryType');
    if (!select || !deliveryTypeSelect) return

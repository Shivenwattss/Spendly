import csv
import io
import os
import re
from datetime import datetime
from collections import defaultdict

from fastapi import FastAPI, Depends, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import create_engine, String, Float, DateTime, select, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker, Session

DATABASE_URL = os.getenv('DATABASE_URL', 'sqlite:///./spendly.db')
engine = create_engine(
    DATABASE_URL,
    connect_args={'check_same_thread': False} if DATABASE_URL.startswith('sqlite') else {},
    pool_pre_ping=True,
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)

class Base(DeclarativeBase):
    pass

class Transaction(Base):
    __tablename__ = 'transactions'
    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    title: Mapped[str] = mapped_column(String(200))
    category: Mapped[str] = mapped_column(String(80), default='Other')
    amount: Mapped[float] = mapped_column(Float)
    type: Mapped[str] = mapped_column(String(10))
    date: Mapped[datetime] = mapped_column(DateTime)
    source: Mapped[str] = mapped_column(String(80), default='Manual')


class SavingsGoal(Base):
    __tablename__ = 'savings_goals'
    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(160))
    target_amount: Mapped[float] = mapped_column(Float)
    saved_amount: Mapped[float] = mapped_column(Float, default=0)
    target_date: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

class Budget(Base):
    __tablename__ = 'budgets'
    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    category: Mapped[str] = mapped_column(String(80), unique=True)
    monthly_limit: Mapped[float] = mapped_column(Float)

class RecurringPayment(Base):
    __tablename__ = 'recurring_payments'
    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(160))
    amount: Mapped[float] = mapped_column(Float)
    cadence: Mapped[str] = mapped_column(String(30), default='monthly')
    next_due: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    kind: Mapped[str] = mapped_column(String(20), default='subscription')

class Debt(Base):
    __tablename__ = 'debts'
    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(160))
    outstanding: Mapped[float] = mapped_column(Float)
    monthly_payment: Mapped[float] = mapped_column(Float, default=0)
    interest_rate: Mapped[float] = mapped_column(Float, default=0)

Base.metadata.create_all(engine)
app = FastAPI(title='Spendly API', version='1.0.0', description='Personal finance tracking and spending analytics API')
app.add_middleware(CORSMiddleware, allow_origins=['*'], allow_methods=['*'], allow_headers=['*'])


def db_session():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def serialize(item: Transaction):
    return {
        'id': item.id, 'title': item.title, 'category': item.category,
        'amount': item.amount, 'type': item.type,
        'date': item.date.isoformat(), 'source': item.source,
    }


def guess_category(description: str, supplied: str | None = None) -> str:
    if supplied and supplied.strip() and supplied.strip().lower() not in {'other', 'uncategorized'}:
        return supplied.strip().title()[:80]
    text = description.lower()
    rules = {
        'Food': ['swiggy', 'zomato', 'restaurant', 'cafe', 'coffee', 'food', 'pizza', 'domino'],
        'Groceries': ['grocery', 'grocer', 'zepto', 'blinkit', 'bigbasket', 'supermarket'],
        'Travel': ['uber', 'ola', 'rapido', 'metro', 'petrol', 'fuel', 'flight', 'train', 'bus'],
        'Shopping': ['amazon', 'flipkart', 'myntra', 'clothing', 'shopping', 'mall'],
        'Bills': ['electricity', 'water bill', 'internet', 'broadband', 'recharge', 'mobile bill'],
        'Entertainment': ['netflix', 'spotify', 'movie', 'cinema', 'prime video', 'hotstar'],
        'Health': ['pharmacy', 'medical', 'hospital', 'doctor', 'medicine'],
        'Education': ['course', 'tuition', 'udemy', 'coursera', 'book'],
        'Salary': ['salary', 'payroll'],
    }
    for category, keywords in rules.items():
        if any(word in text for word in keywords):
            return category
    return supplied.strip().title()[:80] if supplied and supplied.strip() else 'Other'


@app.get('/health')
def health():
    return {'status': 'ok', 'service': 'Spendly API'}

@app.get('/transactions')
def list_transactions(db: Session = Depends(db_session)):
    items = db.scalars(select(Transaction).order_by(Transaction.date.desc(), Transaction.id.desc())).all()
    return [serialize(item) for item in items]

@app.post('/transactions')
def create_transaction(data: dict, db: Session = Depends(db_session)):
    try:
        amount = float(data.get('amount', 0))
        kind = str(data.get('type', '')).lower()
        title = str(data.get('title', data.get('description', ''))).strip()
        date = datetime.fromisoformat(str(data.get('date', datetime.now().isoformat())))
    except (TypeError, ValueError):
        raise HTTPException(422, 'Invalid amount or date')
    if not title or amount <= 0 or amount > 100_000_000 or kind not in {'income', 'expense'}:
        raise HTTPException(422, 'Provide a description, positive amount and type income/expense')
    category = guess_category(title, data.get('category'))
    item = Transaction(title=title[:200], category=category, amount=amount, type=kind,
                       date=date, source=str(data.get('source', 'Manual'))[:80])
    db.add(item); db.commit(); db.refresh(item)
    return serialize(item)

@app.put('/transactions/{item_id}')
def update_transaction(item_id: int, data: dict, db: Session = Depends(db_session)):
    item = db.get(Transaction, item_id)
    if item is None:
        raise HTTPException(404, 'Transaction not found')
    try:
        amount = float(data.get('amount', item.amount))
        kind = str(data.get('type', item.type)).lower()
        date = datetime.fromisoformat(str(data.get('date', item.date.isoformat())))
    except (TypeError, ValueError):
        raise HTTPException(422, 'Invalid amount or date')
    title = str(data.get('title', item.title)).strip()
    if not title or amount <= 0 or amount > 100_000_000 or kind not in {'income', 'expense'}:
        raise HTTPException(422, 'Provide a description, positive amount and type income/expense')
    item.title = title[:200]
    item.amount = amount
    item.type = kind
    item.date = date
    item.category = guess_category(title, data.get('category', item.category))
    item.source = str(data.get('source', item.source))[:80]
    db.commit(); db.refresh(item)
    return serialize(item)

@app.delete('/transactions/{item_id}')
def delete_transaction(item_id: int, db: Session = Depends(db_session)):
    item = db.get(Transaction, item_id)
    if item is None:
        raise HTTPException(404, 'Transaction not found')
    db.delete(item); db.commit()
    return {'deleted': True, 'id': item_id}

@app.post('/transactions/import-csv')
async def import_csv(file: UploadFile = File(...), db: Session = Depends(db_session)):
    if not file.filename or not file.filename.lower().endswith('.csv'):
        raise HTTPException(400, 'Upload a CSV file')
    raw = await file.read()
    try:
        reader = csv.DictReader(io.StringIO(raw.decode('utf-8-sig')))
    except UnicodeDecodeError:
        raise HTTPException(400, 'CSV must be UTF-8 encoded')
    required = {'date', 'description', 'amount', 'type'}
    if not reader.fieldnames or not required.issubset(set(reader.fieldnames)):
        raise HTTPException(400, 'Headers required: date,description,amount,type; category optional')
    count = 0
    skipped = 0
    for row in reader:
        try:
            title = (row.get('description') or '').strip()
            kind = (row.get('type') or '').strip().lower()
            amount = abs(float(row.get('amount', '0')))
            date = datetime.fromisoformat((row.get('date') or '').strip())
            if not title or kind not in {'income', 'expense'} or amount <= 0 or amount > 100_000_000:
                skipped += 1; continue
            category = guess_category(title, row.get('category'))
            db.add(Transaction(title=title[:200], category=category, amount=amount, type=kind,
                               date=date, source='Statement import'))
            count += 1
        except (ValueError, TypeError):
            skipped += 1
    db.commit()
    return {'imported': count, 'skipped': skipped}

@app.get('/analytics')
def analytics(db: Session = Depends(db_session)):
    items = db.scalars(select(Transaction).order_by(Transaction.date.asc())).all()
    income = sum(x.amount for x in items if x.type == 'income')
    expenses = sum(x.amount for x in items if x.type == 'expense')
    by_category = defaultdict(float)
    by_month = defaultdict(lambda: {'income': 0.0, 'expense': 0.0})
    for item in items:
        month = item.date.strftime('%Y-%m')
        by_month[month][item.type] += item.amount
        if item.type == 'expense':
            by_category[item.category or 'Other'] += item.amount
    category_rows = [
        {'category': key, 'amount': round(value, 2), 'share': round((value / expenses * 100), 1) if expenses else 0}
        for key, value in sorted(by_category.items(), key=lambda pair: pair[1], reverse=True)
    ]
    month_rows = [
        {'month': key, 'income': round(value['income'], 2), 'expense': round(value['expense'], 2),
         'savings': round(value['income'] - value['expense'], 2)}
        for key, value in sorted(by_month.items())
    ]
    return {
        'transaction_count': len(items), 'income': round(income, 2), 'expenses': round(expenses, 2),
        'balance': round(income - expenses, 2),
        'savings_rate': round(((income - expenses) / income * 100), 1) if income else 0,
        'categories': category_rows, 'months': month_rows,
    }


@app.get('/insights')
def smart_insights(db: Session = Depends(db_session)):
    """Deterministic, transaction-grounded insights. No LLM or speculative advice."""
    items = db.scalars(select(Transaction).order_by(Transaction.date.asc())).all()
    expenses = [x for x in items if x.type == 'expense']
    incomes = [x for x in items if x.type == 'income']
    total_expense = sum(x.amount for x in expenses)
    total_income = sum(x.amount for x in incomes)
    net = total_income - total_expense
    now = datetime.now()
    current_month_items = [x for x in items if x.date.year == now.year and x.date.month == now.month]
    current_expense = sum(x.amount for x in current_month_items if x.type == 'expense')
    current_income = sum(x.amount for x in current_month_items if x.type == 'income')

    category_totals = defaultdict(float)
    month_totals = defaultdict(lambda: {'income': 0.0, 'expense': 0.0})
    title_occurrences = defaultdict(list)
    for item in items:
        month_totals[item.date.strftime('%Y-%m')][item.type] += item.amount
        if item.type == 'expense':
            category_totals[item.category or 'Other'] += item.amount
            key = re.sub(r'\s+', ' ', item.title.lower()).strip()
            title_occurrences[key].append(item)

    insights = []
    if not items:
        insights.append({'kind': 'getting_started', 'severity': 'info', 'title': 'Start with your first transaction', 'detail': 'Add transactions or import a statement. Spendly will then identify category patterns, large expenses and monthly trends.', 'metric': None})
    else:
        ranked = sorted(category_totals.items(), key=lambda pair: pair[1], reverse=True)
        if ranked and total_expense > 0:
            name, amount = ranked[0]
            share = amount / total_expense * 100
            insights.append({'kind': 'top_category', 'severity': 'info', 'title': f'{name} is your largest expense category', 'detail': f'{name} accounts for {share:.1f}% of all recorded expenses ({amount:,.0f}). This is a spending concentration, not necessarily overspending.', 'metric': {'amount': round(amount, 2), 'share_percent': round(share, 1)}})
        if total_income > 0:
            rate = net / total_income * 100
            if rate < 0:
                severity, title = 'warning', 'Recorded expenses exceed income'
                detail = f'Across all imported and entered transactions, expenses exceed income by {abs(net):,.0f}. Check that the records cover the same period and include all relevant income.'
            elif rate < 10:
                severity, title = 'warning', 'Your recorded savings margin is narrow'
                detail = f'Your net balance is {rate:.1f}% of recorded income. This is based only on transactions currently saved in Spendly.'
            else:
                severity, title = 'positive', 'You are retaining part of your recorded income'
                detail = f'Your recorded net balance is {rate:.1f}% of income. Keep tracking to see whether this pattern continues.'
            insights.append({'kind': 'savings_rate', 'severity': severity, 'title': title, 'detail': detail, 'metric': {'savings_rate': round(rate, 1), 'net': round(net, 2)}})
        month_keys = sorted(month_totals.keys())
        if len(month_keys) >= 2:
            previous_key, latest_key = month_keys[-2], month_keys[-1]
            previous = month_totals[previous_key]['expense']
            latest = month_totals[latest_key]['expense']
            if previous > 0:
                change = (latest - previous) / previous * 100
                direction = 'increased' if change > 0 else 'decreased'
                insights.append({'kind': 'month_comparison', 'severity': 'warning' if change > 20 else 'info', 'title': f'Expenses {direction} month over month', 'detail': f'Recorded expenses changed by {abs(change):.1f}% from {previous_key} ({previous:,.0f}) to {latest_key} ({latest:,.0f}). The latest month may be incomplete.', 'metric': {'change_percent': round(change, 1), 'previous': round(previous, 2), 'latest': round(latest, 2)}})
        if expenses:
            amounts = sorted(x.amount for x in expenses)
            median = amounts[len(amounts)//2] if len(amounts) % 2 else (amounts[len(amounts)//2-1] + amounts[len(amounts)//2]) / 2
            large = sorted([x for x in expenses if x.amount >= max(median * 2, median + 1)], key=lambda x: x.amount, reverse=True)[:3]
            for item in large:
                insights.append({'kind': 'large_transaction', 'severity': 'info', 'title': f'Large recorded expense: {item.title}', 'detail': f'{item.amount:,.0f} on {item.date.strftime("%d %b %Y")} is at least twice the median recorded expense ({median:,.0f}). Confirm it is categorised correctly.', 'metric': {'amount': round(item.amount, 2), 'median_expense': round(median, 2)}})
        recurring = []
        for title, occurrences in title_occurrences.items():
            distinct_days = {x.date.date() for x in occurrences}
            if len(distinct_days) >= 2:
                recurring.append((title, occurrences))
        for title, occurrences in recurring[:3]:
            total = sum(x.amount for x in occurrences)
            insights.append({'kind': 'repeat_merchant', 'severity': 'info', 'title': f'Repeated transaction: {occurrences[0].title}', 'detail': f'This description appears {len(occurrences)} times, totalling {total:,.0f}. It may be recurring; verify the dates and amounts.', 'metric': {'count': len(occurrences), 'total': round(total, 2)}})

    # Simple descriptive run-rate, not a predictive model.
    recent_keys = sorted(month_totals.keys())[-3:]
    recent_expenses = [month_totals[k]['expense'] for k in recent_keys]
    run_rate = round(sum(recent_expenses) / len(recent_expenses), 2) if recent_expenses else 0
    return {
        'transaction_count': len(items),
        'current_month': now.strftime('%Y-%m'),
        'current_month_income': round(current_income, 2),
        'current_month_expenses': round(current_expense, 2),
        'recent_months_used': recent_keys,
        'average_expenses_recent_months': run_rate,
        'insights': insights,
        'disclaimer': 'Insights are deterministic observations from transactions saved in Spendly. They may be incomplete if records are missing or duplicated; they are not financial advice.'
    }


@app.get('/recommendations')
def financial_recommendations(db: Session = Depends(db_session)):
    """Rule-based, explainable recommendations grounded in recorded transactions."""
    items = db.scalars(select(Transaction).order_by(Transaction.date.asc())).all()
    expenses = [x for x in items if x.type == 'expense']
    incomes = [x for x in items if x.type == 'income']
    total_expense = sum(x.amount for x in expenses)
    total_income = sum(x.amount for x in incomes)
    net = total_income - total_expense
    recommendations = []

    if not items:
        recommendations.append({
            'id': 'start_tracking', 'priority': 'info', 'title': 'Build a useful transaction history',
            'reason': 'Spendly needs recorded income and expenses before it can make grounded recommendations.',
            'action': 'Add transactions or import a recent statement, then review your patterns again.',
            'basis': 'No transactions are currently saved.', 'potential_saving': None,
        })
    else:
        if total_income > 0 and net < 0:
            recommendations.append({
                'id': 'cashflow_deficit', 'priority': 'high', 'title': 'Review your cash-flow gap',
                'reason': f'Recorded expenses exceed recorded income by ₹{abs(net):,.0f} across the available history.',
                'action': 'Check that income and expenses cover the same dates, then review discretionary categories and upcoming bills.',
                'basis': 'Total recorded income compared with total recorded expenses.', 'potential_saving': None,
            })
        elif total_income > 0 and net / total_income < 0.10:
            recommendations.append({
                'id': 'thin_margin', 'priority': 'medium', 'title': 'Create a little more breathing room',
                'reason': f'Your recorded net margin is {(net / total_income * 100):.1f}% of income.',
                'action': 'Review optional purchases and recurring charges; try setting aside a small amount immediately after income arrives.',
                'basis': 'Recorded net income divided by recorded income; incomplete records can change this result.', 'potential_saving': None,
            })

        category_totals = defaultdict(float)
        for item in expenses:
            category_totals[item.category or 'Other'] += item.amount
        if total_expense > 0 and category_totals:
            category, amount = max(category_totals.items(), key=lambda pair: pair[1])
            share = amount / total_expense * 100
            if share >= 30:
                recommendations.append({
                    'id': 'category_concentration', 'priority': 'medium', 'title': f'Review your {category.lower()} spending',
                    'reason': f'{category} represents {share:.1f}% of recorded expenses (₹{amount:,.0f}). A large share is a prompt to review, not proof of overspending.',
                    'action': f'Check the individual {category.lower()} transactions and decide whether any purchases can be planned, substituted or reduced.',
                    'basis': 'Category share of all recorded expenses.',
                    'potential_saving': round(amount * 0.05, 2),
                    'potential_saving_label': 'Illustrative 5% reduction scenario, not a guaranteed saving',
                })

        monthly = defaultdict(float)
        for item in expenses:
            monthly[item.date.strftime('%Y-%m')] += item.amount
        keys = sorted(monthly)
        if len(keys) >= 2 and monthly[keys[-2]] > 0:
            previous, latest = monthly[keys[-2]], monthly[keys[-1]]
            change = (latest - previous) / previous * 100
            if change >= 20:
                recommendations.append({
                    'id': 'monthly_spike', 'priority': 'medium', 'title': 'Check what drove the latest spending increase',
                    'reason': f'Expenses in {keys[-1]} are {change:.1f}% higher than {keys[-2]}. The latest month may be incomplete.',
                    'action': 'Compare transactions between the two months and identify one-off purchases versus repeat costs.',
                    'basis': 'Latest recorded calendar month compared with the preceding recorded month.', 'potential_saving': None,
                })

        merchant_groups = defaultdict(list)
        for item in expenses:
            merchant_groups[re.sub(r'\s+', ' ', item.title.lower()).strip()].append(item)
        recurring = [(name, rows) for name, rows in merchant_groups.items()
                     if len({row.date.date() for row in rows}) >= 2]
        if recurring:
            name, rows = max(recurring, key=lambda pair: sum(x.amount for x in pair[1]))
            total = sum(x.amount for x in rows)
            recommendations.append({
                'id': 'repeat_charge_review', 'priority': 'low', 'title': f'Review repeated payments: {rows[0].title}',
                'reason': f'The same description appears on {len(rows)} different dates and totals ₹{total:,.0f}. It may be recurring, but this is not confirmed.',
                'action': 'Check whether this is a subscription or regular bill and cancel or downgrade it only if you no longer need it.',
                'basis': 'Repeated transaction descriptions on multiple dates.', 'potential_saving': None,
            })

    order = {'high': 0, 'medium': 1, 'low': 2, 'info': 3}
    recommendations.sort(key=lambda item: order.get(item['priority'], 4))
    return {
        'recommendations': recommendations,
        'summary': {'transaction_count': len(items), 'recorded_income': round(total_income, 2),
                    'recorded_expenses': round(total_expense, 2), 'recorded_net': round(net, 2)},
        'disclaimer': 'Suggestions are deterministic prompts based only on transactions saved in Spendly. They are not personalised financial, tax or investment advice. Verify records and consider your obligations before acting.',
    }


@app.get('/forecast')
def spending_forecast(db: Session = Depends(db_session)):
    """Transparent baseline forecast. Uses completed months plus current-month run rate; not ML."""
    items = db.scalars(select(Transaction).order_by(Transaction.date.asc())).all()
    now = datetime.now()
    month_map = defaultdict(float)
    for item in items:
        if item.type == 'expense':
            month_map[item.date.strftime('%Y-%m')] += item.amount

    current_key = now.strftime('%Y-%m')
    current_spend = round(month_map.get(current_key, 0.0), 2)
    days_elapsed = max(now.day, 1)
    days_in_month = (datetime(now.year + (now.month == 12), 1 if now.month == 12 else now.month + 1, 1) - datetime(now.year, now.month, 1)).days
    run_rate_projection = round((current_spend / days_elapsed) * days_in_month, 2) if current_spend else 0.0

    completed_keys = sorted(k for k in month_map if k < current_key)
    recent_completed = completed_keys[-3:]
    historical_values = [month_map[k] for k in recent_completed]
    historical_average = round(sum(historical_values) / len(historical_values), 2) if historical_values else None

    # A conservative blended estimate when there is historical data; otherwise show run-rate only.
    if historical_average is not None and current_spend > 0:
        projected = round((run_rate_projection * 0.6) + (historical_average * 0.4), 2)
        method = '60% current-month run rate + 40% average of recent completed months'
    elif current_spend > 0:
        projected = run_rate_projection
        method = 'Current-month daily run rate; historical months unavailable'
    elif historical_average is not None:
        projected = historical_average
        method = 'Average of recent completed months; no current-month expenses recorded'
    else:
        projected = None
        method = 'Insufficient transaction history'

    return {
        'month': current_key,
        'current_month_expenses': current_spend,
        'days_elapsed': days_elapsed,
        'days_in_month': days_in_month,
        'run_rate_projection': run_rate_projection,
        'historical_months_used': recent_completed,
        'historical_monthly_average': historical_average,
        'projected_month_end_expenses': projected,
        'method': method,
        'confidence': 'low' if len(recent_completed) < 2 else 'moderate',
        'disclaimer': 'This is a simple baseline estimate, not a trained predictive model. It assumes recorded spending pace is reasonably representative and may be inaccurate when the month is incomplete or data is missing.'
    }


@app.get('/anomalies')
def spending_anomalies(db: Session = Depends(db_session)):
    """Flags unusually large expenses using a robust median/MAD rule; requires enough data."""
    items = db.scalars(select(Transaction).order_by(Transaction.date.desc())).all()
    expenses = [x for x in items if x.type == 'expense']
    if len(expenses) < 5:
        return {'method': 'median absolute deviation (MAD)', 'sample_size': len(expenses), 'minimum_sample_size': 5,
                'anomalies': [], 'message': 'Add at least five expense transactions before Spendly flags unusual amounts.'}

    values = sorted(x.amount for x in expenses)
    n = len(values)
    median = values[n // 2] if n % 2 else (values[n // 2 - 1] + values[n // 2]) / 2
    deviations = sorted(abs(v - median) for v in values)
    mad = deviations[n // 2] if n % 2 else (deviations[n // 2 - 1] + deviations[n // 2]) / 2
    if mad > 0:
        threshold = median + (3.5 * 1.4826 * mad)
        method = 'median + 3.5 × scaled MAD'
    else:
        q1 = values[int((n - 1) * 0.25)]
        q3 = values[int((n - 1) * 0.75)]
        iqr = q3 - q1
        threshold = q3 + 1.5 * iqr if iqr > 0 else median * 2
        method = 'upper IQR fence' if iqr > 0 else 'twice the median (zero MAD/IQR fallback)'

    flagged = [x for x in expenses if x.amount > threshold]
    flagged.sort(key=lambda x: x.amount, reverse=True)
    return {
        'method': method,
        'sample_size': len(expenses),
        'median_expense': round(median, 2),
        'threshold': round(threshold, 2),
        'anomalies': [
            {'id': x.id, 'title': x.title, 'category': x.category, 'amount': round(x.amount, 2),
             'date': x.date.isoformat(), 'source': x.source,
             'multiple_of_median': round(x.amount / median, 2) if median else None}
            for x in flagged[:20]
        ],
        'message': 'These are statistical outliers by amount, not proof of fraud or unnecessary spending.'
    }


@app.post('/assistant/chat')
def assistant_chat(data: dict, db: Session = Depends(db_session)):
    """Transaction-grounded rule-based financial assistant MVP (no external LLM)."""
    question = str(data.get('message', '')).strip()
    if not question:
        raise HTTPException(422, 'Message cannot be empty')
    if len(question) > 1000:
        raise HTTPException(422, 'Message is too long (maximum 1000 characters)')

    items = db.scalars(select(Transaction).order_by(Transaction.date.asc())).all()
    if not items:
        return {
            'answer': "I don't have any transactions to analyse yet. Add a few transactions or import a CSV statement, then ask me about your spending, income, savings or affordability.",
            'source': 'Spendly transaction data',
            'suggestions': ['How much did I spend this month?', 'Where am I spending the most?', 'Can I afford a purchase of ₹20,000?']
        }

    total_income = sum(x.amount for x in items if x.type == 'income')
    total_expense = sum(x.amount for x in items if x.type == 'expense')
    net = total_income - total_expense
    savings_rate = (net / total_income * 100) if total_income else 0.0
    expenses = [x for x in items if x.type == 'expense']
    category_totals = defaultdict(float)
    for item in expenses:
        category_totals[item.category or 'Other'] += item.amount
    top_categories = sorted(category_totals.items(), key=lambda x: x[1], reverse=True)

    now = datetime.now()
    current_month = [x for x in items if x.date.year == now.year and x.date.month == now.month]
    month_income = sum(x.amount for x in current_month if x.type == 'income')
    month_expense = sum(x.amount for x in current_month if x.type == 'expense')
    month_net = month_income - month_expense

    q = question.lower()
    money_match = re.search(r'(?:₹|rs\.?\s*|inr\s*)\s*([0-9][0-9,]*(?:\.\d+)?)|\b([0-9][0-9,]*(?:\.\d+)?)\s*(?:rupees|rs\.?|inr)\b', q)
    purchase_amount = None
    if money_match:
        raw_amount = next((g for g in money_match.groups() if g), None)
        if raw_amount:
            try:
                purchase_amount = float(raw_amount.replace(',', ''))
            except ValueError:
                pass

    if any(word in q for word in ['afford', 'buy', 'purchase', 'should i get', 'can i get']) and purchase_amount:
        # Use current-month net cash flow as a conservative signal, not a credit/financial approval.
        if month_net >= purchase_amount:
            verdict = 'Your recorded net cash flow this month is enough to cover that amount on paper.'
        elif net >= purchase_amount:
            verdict = 'Your all-time recorded net balance is higher than that amount, but this month’s recorded cash flow is not enough to cover it.'
        else:
            verdict = 'Based on the transactions recorded, that purchase would exceed your current recorded net balance.'
        answer = (f'For a purchase of ₹{purchase_amount:,.0f}: {verdict} '
                  f'This month you have recorded ₹{month_income:,.0f} income and ₹{month_expense:,.0f} expenses (net ₹{month_net:,.0f}). '
                  f'Your all-time recorded net balance is ₹{net:,.0f}. Keep upcoming bills, savings goals and emergency funds in mind; this is a simple estimate, not personalised regulated financial advice.')
    elif any(word in q for word in ['top categor', 'spend most', 'spending most', 'biggest expense', 'where am i spending', 'where do i spend', 'highest spend']):
        if top_categories:
            name, amount = top_categories[0]
            share = amount / total_expense * 100 if total_expense else 0
            answer = f'Your highest recorded expense category is {name}: ₹{amount:,.0f}, which is {share:.1f}% of your total recorded expenses of ₹{total_expense:,.0f}.'
            if len(top_categories) > 1:
                second_name, second_amount = top_categories[1]
                answer += f' The next highest is {second_name} at ₹{second_amount:,.0f}.'
        else:
            answer = 'There are no recorded expenses yet, so I cannot rank your spending categories.'
    elif any(word in q for word in ['this month', 'current month', 'monthly spend', 'month spend']) and any(word in q for word in ['spend', 'expense', 'spent', 'income', 'save', 'cash flow', 'summary', 'how much']):
        answer = f'For {now.strftime("%B %Y")}, your recorded income is ₹{month_income:,.0f}, expenses are ₹{month_expense:,.0f}, and net cash flow is ₹{month_net:,.0f}.'
    elif any(word in q for word in ['saving rate', 'savings rate', 'how much do i save', 'how much can i save', 'save this month', 'saved']):
        answer = f'Across all recorded transactions, your net balance is ₹{net:,.0f} and your savings rate is {savings_rate:.1f}% of recorded income. For {now.strftime("%B")}, your net cash flow so far is ₹{month_net:,.0f}. This is based only on transactions entered or imported into Spendly.'
    elif any(word in q for word in ['total expense', 'total spending', 'spent overall', 'how much have i spent', 'total spent']):
        answer = f'You have recorded ₹{total_expense:,.0f} in expenses and ₹{total_income:,.0f} in income across {len(items)} transactions. Your recorded net balance is ₹{net:,.0f}.'
    elif any(word in q for word in ['income', 'earned', 'salary']) and not any(word in q for word in ['expense', 'spend']):
        answer = f'Your total recorded income is ₹{total_income:,.0f} across {sum(1 for x in items if x.type == "income")} income transactions. This month: ₹{month_income:,.0f}.'
    elif any(word in q for word in ['advice', 'improve', 'reduce', 'recommend', 'tip', 'suggest']):
        if top_categories:
            name, amount = top_categories[0]
            share = amount / total_expense * 100 if total_expense else 0
            answer = f'A useful place to review is {name}: it accounts for {share:.1f}% of your recorded expenses (₹{amount:,.0f}). Try setting a realistic limit for this category and compare it next month. Your recorded savings rate is {savings_rate:.1f}%. '
        else:
            answer = 'Keep recording income and expenses consistently. Once you have enough history, I can highlight the categories where spending is concentrated.'
    else:
        top_text = ', '.join(f'{name} ₹{amount:,.0f}' for name, amount in top_categories[:3]) or 'no expense categories yet'
        answer = (f'Here is your current snapshot: recorded income ₹{total_income:,.0f}, expenses ₹{total_expense:,.0f}, '
                  f'net balance ₹{net:,.0f}, savings rate {savings_rate:.1f}%. Largest categories: {top_text}. '
                  'Try asking “Where am I spending the most?”, “How much did I spend this month?” or “Can I afford ₹20,000?”')

    return {
        'answer': answer,
        'source': f'Based on {len(items)} saved transactions',
        'suggestions': ['Where am I spending the most?', 'How much did I spend this month?', 'Can I afford ₹20,000?']
    }


# --- Financial planning APIs ---
def _valid_positive(value, label):
    try: number = float(value)
    except (TypeError, ValueError): raise HTTPException(422, f'{label} must be a number')
    if number <= 0 or number > 1_000_000_000: raise HTTPException(422, f'{label} must be positive')
    return number

def _goal_json(x):
    remaining=max(0, x.target_amount-x.saved_amount)
    days=(x.target_date.date()-datetime.now().date()).days if x.target_date else None
    months=max(1, (days or 30)/30)
    return {'id':x.id,'name':x.name,'target_amount':x.target_amount,'saved_amount':x.saved_amount,'remaining':remaining,'progress':round(min(100,x.saved_amount/x.target_amount*100),1),'target_date':x.target_date.isoformat() if x.target_date else None,'suggested_monthly_contribution':round(remaining/months,2)}

@app.get('/goals')
def get_goals(db: Session = Depends(db_session)):
    return [_goal_json(x) for x in db.scalars(select(SavingsGoal).order_by(SavingsGoal.id.desc())).all()]

@app.post('/goals')
def add_goal(data: dict, db: Session = Depends(db_session)):
    name=str(data.get('name','')).strip(); target=_valid_positive(data.get('target_amount'), 'target_amount'); saved=float(data.get('saved_amount',0) or 0)
    if not name or saved < 0 or saved > target: raise HTTPException(422,'Enter a name and saved amount between zero and target')
    due=datetime.fromisoformat(data['target_date']) if data.get('target_date') else None
    x=SavingsGoal(name=name[:160],target_amount=target,saved_amount=saved,target_date=due); db.add(x); db.commit(); db.refresh(x); return _goal_json(x)

@app.patch('/goals/{goal_id}')
def update_goal(goal_id:int, data:dict, db:Session=Depends(db_session)):
    x=db.get(SavingsGoal,goal_id)
    if not x: raise HTTPException(404,'Goal not found')
    if 'name' in data: x.name=str(data['name']).strip()[:160]
    if 'target_amount' in data: x.target_amount=_valid_positive(data['target_amount'],'target_amount')
    if 'saved_amount' in data: x.saved_amount=float(data['saved_amount'])
    if x.saved_amount < 0 or x.saved_amount > x.target_amount: raise HTTPException(422,'Saved amount must be between zero and target')
    if 'target_date' in data: x.target_date=datetime.fromisoformat(data['target_date']) if data['target_date'] else None
    db.commit(); db.refresh(x); return _goal_json(x)

@app.delete('/goals/{goal_id}')
def delete_goal(goal_id:int, db:Session=Depends(db_session)):
    x=db.get(SavingsGoal,goal_id)
    if not x: raise HTTPException(404,'Goal not found')
    db.delete(x); db.commit(); return {'deleted':True}

@app.get('/budgets')
def get_budgets(db:Session=Depends(db_session)):
    rows=db.scalars(select(Budget).order_by(Budget.category)).all(); now=datetime.now()
    tx=db.scalars(select(Transaction).where(Transaction.type=='expense',func.strftime('%Y-%m',Transaction.date)==now.strftime('%Y-%m'))).all()
    totals=defaultdict(float)
    for t in tx: totals[t.category]+=t.amount
    return [{'id':b.id,'category':b.category,'monthly_limit':b.monthly_limit,'spent':round(totals[b.category],2),'remaining':round(b.monthly_limit-totals[b.category],2),'percent':round(totals[b.category]/b.monthly_limit*100,1)} for b in rows]

@app.post('/budgets')
def save_budget(data:dict, db:Session=Depends(db_session)):
    category=str(data.get('category','')).strip().title(); limit=_valid_positive(data.get('monthly_limit'),'monthly_limit')
    if not category: raise HTTPException(422,'Category is required')
    x=db.scalar(select(Budget).where(Budget.category==category))
    if x: x.monthly_limit=limit
    else: x=Budget(category=category,monthly_limit=limit); db.add(x)
    db.commit(); db.refresh(x); return {'id':x.id,'category':x.category,'monthly_limit':x.monthly_limit}

@app.delete('/budgets/{budget_id}')
def remove_budget(budget_id:int, db:Session=Depends(db_session)):
    x=db.get(Budget,budget_id)
    if not x: raise HTTPException(404,'Budget not found')
    db.delete(x); db.commit(); return {'deleted':True}

@app.get('/recurring')
def get_recurring(db:Session=Depends(db_session)):
    return [{'id':x.id,'name':x.name,'amount':x.amount,'cadence':x.cadence,'next_due':x.next_due.isoformat() if x.next_due else None,'kind':x.kind} for x in db.scalars(select(RecurringPayment).order_by(RecurringPayment.id.desc())).all()]

@app.post('/recurring')
def add_recurring(data:dict, db:Session=Depends(db_session)):
    name=str(data.get('name','')).strip(); amount=_valid_positive(data.get('amount'),'amount'); cadence=str(data.get('cadence','monthly')).lower(); kind=str(data.get('kind','subscription')).lower()
    if not name or cadence not in {'weekly','monthly','quarterly','yearly'} or kind not in {'subscription','bill','emi'}: raise HTTPException(422,'Invalid name, cadence or payment kind')
    due=datetime.fromisoformat(data['next_due']) if data.get('next_due') else None
    x=RecurringPayment(name=name[:160],amount=amount,cadence=cadence,kind=kind,next_due=due); db.add(x); db.commit(); db.refresh(x); return {'id':x.id,'name':x.name,'amount':x.amount,'cadence':x.cadence,'kind':x.kind,'next_due':x.next_due.isoformat() if x.next_due else None}

@app.delete('/recurring/{payment_id}')
def delete_recurring(payment_id:int, db:Session=Depends(db_session)):
    x=db.get(RecurringPayment,payment_id)
    if not x: raise HTTPException(404,'Payment not found')
    db.delete(x); db.commit(); return {'deleted':True}

@app.get('/debts')
def get_debts(db:Session=Depends(db_session)):
    return [{'id':x.id,'name':x.name,'outstanding':x.outstanding,'monthly_payment':x.monthly_payment,'interest_rate':x.interest_rate} for x in db.scalars(select(Debt).order_by(Debt.id.desc())).all()]

@app.post('/debts')
def add_debt(data:dict, db:Session=Depends(db_session)):
    name=str(data.get('name','')).strip(); outstanding=_valid_positive(data.get('outstanding'),'outstanding'); payment=float(data.get('monthly_payment',0) or 0); rate=float(data.get('interest_rate',0) or 0)
    if not name or payment<0 or rate<0 or rate>100: raise HTTPException(422,'Invalid debt details')
    x=Debt(name=name[:160],outstanding=outstanding,monthly_payment=payment,interest_rate=rate); db.add(x); db.commit(); db.refresh(x); return {'id':x.id,'name':x.name,'outstanding':x.outstanding,'monthly_payment':x.monthly_payment,'interest_rate':x.interest_rate}

@app.delete('/debts/{debt_id}')
def delete_debt(debt_id:int, db:Session=Depends(db_session)):
    x=db.get(Debt,debt_id)
    if not x: raise HTTPException(404,'Debt not found')
    db.delete(x); db.commit(); return {'deleted':True}

@app.get('/planning/summary')
def planning_summary(db:Session=Depends(db_session)):
    goals=db.scalars(select(SavingsGoal)).all(); debts=db.scalars(select(Debt)).all(); payments=db.scalars(select(RecurringPayment)).all()
    return {'goals_count':len(goals),'goals_target':sum(x.target_amount for x in goals),'goals_saved':sum(x.saved_amount for x in goals),'debt_outstanding':sum(x.outstanding for x in debts),'monthly_debt_payments':sum(x.monthly_payment for x in debts),'monthly_recurring_estimate':sum(x.amount*(52/12 if x.cadence=='weekly' else 1 if x.cadence=='monthly' else 1/3 if x.cadence=='quarterly' else 1/12) for x in payments)}



@app.get('/financial-health')
def financial_health(db: Session = Depends(db_session)):
    """A transparent educational score from 0-100 based on recorded data."""
    tx = db.scalars(select(Transaction)).all()
    income = sum(x.amount for x in tx if x.type == 'income')
    expenses = sum(x.amount for x in tx if x.type == 'expense')
    net = income - expenses
    score = 50
    factors = []
    if income > 0:
        savings_rate = net / income
        if savings_rate >= 0.20:
            score += 20; factors.append({'factor':'Savings margin','status':'positive','detail':'Recorded savings margin is at least 20%.'})
        elif savings_rate >= 0.10:
            score += 12; factors.append({'factor':'Savings margin','status':'positive','detail':'Recorded savings margin is between 10% and 20%.'})
        elif savings_rate > 0:
            score += 5; factors.append({'factor':'Savings margin','status':'neutral','detail':'There is a positive recorded margin, but it is below 10%.'})
        else:
            score -= 15; factors.append({'factor':'Savings margin','status':'warning','detail':'Recorded expenses meet or exceed recorded income.'})
    else:
        factors.append({'factor':'Income history','status':'unknown','detail':'Add income transactions to assess your savings margin.'})
    budgets = db.scalars(select(Budget)).all()
    if budgets:
        score += 5
        factors.append({'factor':'Budget coverage','status':'positive','detail':f'{len(budgets)} category budget(s) configured.'})
    else:
        factors.append({'factor':'Budget coverage','status':'unknown','detail':'Set category budgets to compare planned and actual spending.'})
    debts = db.scalars(select(Debt)).all()
    debt_payment = sum(x.monthly_payment for x in debts)
    if income > 0 and debt_payment > 0:
        ratio = debt_payment / income
        if ratio <= 0.20: score += 5; status='positive'
        elif ratio <= 0.35: status='neutral'
        else: score -= 10; status='warning'
        factors.append({'factor':'Recorded debt payments','status':status,'detail':f'Monthly recorded debt payments are {ratio:.0%} of recorded income.'})
    elif not debts:
        factors.append({'factor':'Debt tracking','status':'unknown','detail':'No debts are recorded; this does not prove that you have no debt.'})
    goals = db.scalars(select(SavingsGoal)).all()
    if goals:
        score += 5
        factors.append({'factor':'Savings goals','status':'positive','detail':f'{len(goals)} savings goal(s) are being tracked.'})
    else:
        factors.append({'factor':'Savings goals','status':'unknown','detail':'Create a savings goal to track progress toward a target.'})
    score = max(0, min(100, score))
    label = 'Strong' if score >= 80 else 'Building' if score >= 60 else 'Needs attention'
    return {'score':score,'label':label,'recorded_income':round(income,2),'recorded_expenses':round(expenses,2),'recorded_net':round(net,2),'factors':factors,'disclaimer':'Educational indicator based only on the transactions, budgets, goals and debts recorded in Spendly. It is not a credit score or professional financial assessment.'}


@app.post('/assistant/ollama')
def assistant_ollama(data:dict, db:Session=Depends(db_session)):
    # Optional local LLM. Set OLLAMA_MODEL (e.g. llama3.2) and run Ollama locally.
    import urllib.request, json as jsonlib
    model=os.getenv('OLLAMA_MODEL','')
    if not model: raise HTTPException(503,'Ollama is disabled. Set OLLAMA_MODEL in the backend environment to enable it.')
    message=str(data.get('message','')).strip()
    if not message: raise HTTPException(422,'Message is required')
    tx=db.scalars(select(Transaction).order_by(Transaction.date.desc()).limit(500)).all()
    income=sum(x.amount for x in tx if x.type=='income'); expense=sum(x.amount for x in tx if x.type=='expense')
    cats=defaultdict(float)
    for x in tx:
        if x.type=='expense': cats[x.category]+=x.amount
    context={'record_count':len(tx),'recorded_income':round(income,2),'recorded_expenses':round(expense,2),'net':round(income-expense,2),'expense_categories':dict(cats)}
    prompt='You are Spendly, a cautious personal finance assistant. Use only the supplied financial context for personal figures. If information is missing, say so. Do not claim to execute transactions or give regulated investment/tax advice.\nFinancial context: '+jsonlib.dumps(context)+'\nUser question: '+message
    payload=jsonlib.dumps({'model':model,'prompt':prompt,'stream':False}).encode()
    req=urllib.request.Request(os.getenv('OLLAMA_URL','http://127.0.0.1:11434/api/generate'),data=payload,headers={'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(req,timeout=90) as response: result=jsonlib.loads(response.read().decode())
        return {'answer':result.get('response','No response from Ollama.'),'model':model,'context_records':len(tx)}
    except Exception as exc: raise HTTPException(502,f'Could not reach Ollama: {exc}')

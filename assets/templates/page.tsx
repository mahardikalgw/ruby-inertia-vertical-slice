import { Head, Link } from '@inertiajs/react'
import AppLayout from '@/layouts/app-layout'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { EmptyState } from '@/components/workspace/empty-state'
import { Pagination } from '@/components/workspace/pagination'
import { ResultCount } from '@/components/workspace/result-count'
import { SearchField } from '@/components/workspace/search-field'
import { tableRecipe } from '@/components/workspace/table-recipe'
import type { RecordsIndexProps } from '@/lib/types'

// One page = layout + Head + composition. No fetch, no local copy of the records, no status->label
// map: filters are a server round trip, labels arrive as shared props.
export default function RecordsIndex({ records, pagination, filters, empty_state, can }: RecordsIndexProps) {
  return (
    <AppLayout title="Records" context={<ResultCount total={pagination.total} />}>
      <Head title="Records" />

      <div className="flex flex-wrap items-center justify-between gap-3">
        <SearchField action="/records" value={filters.q} params={{ status: filters.status ?? '' }} debounceMs={300} />
        {can.create ? (
          <Button asChild>
            <Link href="/records/new">{empty_state.action_label}</Link>
          </Button>
        ) : null}
      </div>

      <Card>
        <CardContent className="p-0">
          {records.length === 0 ? (
            <EmptyState title={empty_state.title} body={empty_state.body} />
          ) : (
            <>
              <Table>
                <TableHeader className={tableRecipe.header}>
                  <TableRow>
                    <TableHead className={tableRecipe.head}>Nomor</TableHead>
                    <TableHead className={tableRecipe.head}>Judul</TableHead>
                    <TableHead className={`${tableRecipe.head} text-right`}>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {records.map((record) => (
                    <TableRow key={record.id} className={tableRecipe.row}>
                      <TableCell className={tableRecipe.numeric}>{record.number}</TableCell>
                      <TableCell className={tableRecipe.cell}>
                        <Link href={`/records/${record.number}`} className="hover:underline">
                          {record.title}
                        </Link>
                      </TableCell>
                      <TableCell className={tableRecipe.cell}>{record.status_label}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>

              <Pagination
                pagination={pagination}
                href={(page) => `/records?${new URLSearchParams({ ...filters, page: String(page) }).toString()}`}
              />
            </>
          )}
        </CardContent>
      </Card>
    </AppLayout>
  )
}

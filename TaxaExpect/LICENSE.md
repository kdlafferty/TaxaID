# GNU General Public License v3.0 or later

Copyright (c) 2026 Kevin D. Lafferty, U.S. Geological Survey

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program. If not, see <https://www.gnu.org/licenses/>.

## Why GPL?

TaxaExpect uses GPL (>= 3) because it depends on glmmTMB, which is
GPL-licensed. Since TaxaExpect is only in Suggests (never Imports) for
downstream TaxaID packages, this does not propagate the GPL obligation to the
rest of the ecosystem.

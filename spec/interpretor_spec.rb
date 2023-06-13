require 'date'

require 'interpretor.rb'

RSpec.describe ::Interpretor do
  let :users do
    ::Relation.new(id: :numeric, name: :string)
              .bulk_insert([
      [1, 'John'],
      [2, 'Jane'],
      [3, 'Peter']
    ])
  end

  let :admins do
    ::Relation.new(id: :numeric, name: :string)
              .bulk_insert([
      [1, 'John'],
      [2, 'Anne']
    ])
  end

  let :user_roles do
    ::Relation.new(role: :string)
              .bulk_insert([
      ['user'],
      ['manager']
    ])
  end

  let :projects do
    ::Relation.new(id: :numeric, name: :string, start_date: :date)
              .bulk_insert([
      [1, 'Netvisor', ::Date.new(2023, 1, 1)],
      [2, 'Severa', ::Date.new(2023, 3, 22)]
    ])
  end

  let :data do
    {
      Users:     users,
      Admins:    admins,
      UserRoles: user_roles,
      Projects:  projects
    }
  end

  context 'set operations' do
    it 'should perform intersection correctly' do
      lines = ['Users & Admins -> Res']
      res_data = subject.run(lines, data)
      expect(res_data[:Res].to_a).to eq([{ id: 1, name: 'John' }])
    end

    it 'should perform union correctly' do
      lines = ['Users | Admins -> Res']
      res_data = subject.run(lines, data)
      expect(res_data[:Res].to_a).to eq([
        { id: 1, name: 'John' },
        { id: 2, name: 'Jane' },
        { id: 3, name: 'Peter' },
        { id: 2, name: 'Anne' }
      ])
    end

    it 'should perform difference corerctly' do
      lines = ['Users \ Admins -> Res']
      res_data = subject.run(lines, data)
      expect(res_data[:Res].to_a).to eq([
        { id: 2, name: 'Jane' },
        { id: 3, name: 'Peter' }
      ])
    end

    it 'should perform product correctly' do
      lines = ['Users * Admins -> Res']
      res_data = subject.run(lines, data)
      expect(res_data[:Res].to_a).to eq([
        { 'Users.id': 1, 'Users.name': 'John', 'Admins.id': 1, 'Admins.name': 'John' },
        { 'Users.id': 1, 'Users.name': 'John', 'Admins.id': 2, 'Admins.name': 'Anne' },
        { 'Users.id': 2, 'Users.name': 'Jane', 'Admins.id': 1, 'Admins.name': 'John' },
        { 'Users.id': 2, 'Users.name': 'Jane', 'Admins.id': 2, 'Admins.name': 'Anne' },
        { 'Users.id': 3, 'Users.name': 'Peter', 'Admins.id': 1, 'Admins.name': 'John' },
        { 'Users.id': 3, 'Users.name': 'Peter', 'Admins.id': 2, 'Admins.name': 'Anne' }
      ])
    end

    it 'should perform product correctly when all attribute names are unique' do
      lines = ['Users * UserRoles -> Res']
      res_data = subject.run(lines, data)
      expect(res_data[:Res].to_a).to eq([
        { id: 1, name: 'John', role: 'user' },
        { id: 1, name: 'John', role: 'manager' },
        { id: 2, name: 'Jane', role: 'user' },
        { id: 2, name: 'Jane', role: 'manager' },
        { id: 3, name: 'Peter', role: 'user' },
        { id: 3, name: 'Peter', role: 'manager' }
      ])
    end

    it 'should interpret a line with multiple set operations correctly' do
      lines = ['(Users \ Admins) | (Admins \ Users) -> Res']
      res_data = subject.run(lines, data)
      expect(res_data[:Res].to_a).to eq([
        { id: 2, name: 'Jane' },
        { id: 3, name: 'Peter' },
        { id: 2, name: 'Anne' }
      ])
    end

    it 'should perform multiple lines with set operations correctly' do
      lines = [
        'Users \ Admins -> R1',
        'Admins \ Users -> R2',
        'R1 | R2 -> Res'
      ]
      res_data = subject.run(lines, data)
      expect(res_data[:Res].to_a).to eq([
        { id: 2, name: 'Jane' },
        { id: 3, name: 'Peter' },
        { id: 2, name: 'Anne' }
      ])
    end

    context 'with relations whose columns do not match' do
      it 'should not perform difference' do
        expect { subject.run(['Users \ UserRoles -> Res'], data) }.to raise_error(
          ArgumentError, /Cannot apply DIFFERENCE: relations' attribute types don't match/
        )
      end

      it 'should not perform intersection' do
        expect { subject.run(['Users & UserRoles -> Res'], data) }.to raise_error(
          ArgumentError, /Cannot apply INTERSECTION: relations' attribute types don't match/
        )
      end

      it 'should not perform union' do
        expect { subject.run(['Users | UserRoles -> Res'], data) }.to raise_error(
          ArgumentError, /Cannot apply UNION: relations' attribute types don't match/
        )
      end
    end
  end

  context 'relational algebra operations' do
    context 'projection' do
      it 'should not perform projection if there is no such attribute' do
        expect { subject.run(['Users[year_of_birth] -> Res'], data) }.to raise_error(
          ArgumentError, "Cannot apply PROJECTION(year_of_birth): relation's attributes do not include year_of_birth"
        )
      end

      it 'should perform projection with one attribute correctly' do
        lines = ['Users[name] -> Res']
        res_data = subject.run(lines, data)
        expect(res_data[:Res].to_a).to eq([
          { name: 'John' },
          { name: 'Jane' },
          { name: 'Peter' }
        ])
      end

      it 'should perform projection with multiple attributes correctly' do
        lines = ['Projects[start_date, name] -> Res']
        res_data = subject.run(lines, data)
        expect(res_data[:Res].to_a).to eq([
          { start_date: ::Date.new(2023, 1, 1), name: 'Netvisor' },
          { start_date: ::Date.new(2023, 3, 22), name: 'Severa' }
        ])
      end
    end

    context 'limit' do
      it 'should perform limit correctly' do
        lines = ['(Users * Admins)[Users.name=Admins.name] -> Res']
        res_data = subject.run(lines, data)
        expect(res_data[:Res].to_a).to eq([
          { 'Users.id': 1, 'Users.name': 'John', 'Admins.id': 1, 'Admins.name': 'John' }
        ])
      end

      context 'simplified limit' do
        it 'should peform simplified limit with GT operator correctly' do
          lines = ['Users[id>1] -> Res']
          res_data = subject.run(lines, data)
          expect(res_data[:Res].to_a).to eq([
            { id: 2, name: 'Jane' },
            { id: 3, name: 'Peter' }
          ])
        end

        it 'should perform simplified limit with EQ operator correctly' do
          lines = ["Users[name='John'] -> Res"]
          res_data = subject.run(lines, data)
          expect(res_data[:Res].to_a).to eq([
            { id: 1, name: 'John' }
          ])
        end
      end

      context 'invalid expressions' do
        it 'should not perform limit if there is no such attribute' do
          expect { subject.run(['Users[year_of_birth=1996] -> Res'], data) }.to raise_error(
            ArgumentError, "Cannot apply LIMIT(year_of_birth=1996): relation's attributes do not include year_of_birth"
          )
        end

        it 'should not perform limit if the second attribute does not exist' do
          expect { subject.run(['Users[id=second_id] -> Res'], data) }.to raise_error(
            ArgumentError, "Cannot apply LIMIT(id=second_id): relation's attributes do not include second_id"
          )
        end

        context 'simplified limit with mismatching value type' do
          it 'should raise an exception if the attribute is a string and the value is a number' do
            expect { subject.run(['Users[name=1] -> Res'], data) }.to raise_error(
              ArgumentError, "Cannot apply LIMIT(name=1): 1 is not a string"
            )
          end

          it 'should raise an exception if the attribute is a number and the value is a string' do
            expect { subject.run(["Users[id='John'] -> Res"], data) }.to raise_error(
              ArgumentError, "Cannot apply LIMIT(id='John'): 'John' cannot be parsed into a number"
            )
          end
        end
      end
    end
  end
end
